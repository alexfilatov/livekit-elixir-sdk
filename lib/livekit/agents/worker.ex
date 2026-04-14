defmodule Livekit.Agents.Worker do
  @moduledoc """
  Worker process that manages agent deployments and job execution.

  The Worker is responsible for:
  - Registering with LiveKit server as an available agent worker
  - Receiving and processing job dispatch requests
  - Managing agent session lifecycles
  - Load balancing across multiple agent instances
  - Health monitoring and reporting
  """

  use GenServer
  require Logger

  alias Livekit.Agents.{AgentSession, VoiceAgent, JobContext}
  alias Livekit.{AccessToken, RoomServiceClient}

  defmodule Config do
    @moduledoc """
    Configuration for Worker.
    """

    @type entrypoint_fn :: (JobContext.t() -> :ok | {:error, term()})

    @type t :: %__MODULE__{
      worker_id: String.t(),
      server_url: String.t(),
      api_key: String.t(),
      api_secret: String.t(),
      entrypoint: entrypoint_fn(),
      max_concurrent_jobs: pos_integer(),
      health_check_interval: pos_integer(),
      reconnect_attempts: pos_integer(),
      worker_metadata: map()
    }

    defstruct [
      worker_id: nil,
      server_url: "ws://localhost:7880",
      api_key: nil,
      api_secret: nil,
      entrypoint: nil,
      max_concurrent_jobs: 10,
      health_check_interval: 30_000,
      reconnect_attempts: 5,
      worker_metadata: %{}
    ]
  end

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
      config: Config.t(),
      connection: pid() | nil,
      registered: boolean(),
      active_jobs: map(),
      job_count: non_neg_integer(),
      health_status: :healthy | :degraded | :unhealthy,
      last_heartbeat: DateTime.t() | nil,
      metrics: map()
    }

    defstruct [
      :config,
      :connection,
      registered: false,
      active_jobs: %{},
      job_count: 0,
      health_status: :healthy,
      last_heartbeat: nil,
      metrics: %{
        jobs_processed: 0,
        jobs_failed: 0,
        total_uptime: 0,
        avg_job_duration: 0,
        last_job_at: nil
      }
    ]
  end

  # Client API

  @doc """
  Starts a Worker with the given configuration.
  """
  @spec start_link(Config.t(), GenServer.options()) :: GenServer.on_start()
  def start_link(config, opts \\ []) do
    # Generate worker ID if not provided
    config = %{config |
      worker_id: config.worker_id || generate_worker_id(),
      worker_metadata: Map.merge(%{
        elixir_version: System.version(),
        otp_version: System.otp_release(),
        start_time: DateTime.utc_now()
      }, config.worker_metadata)
    }

    GenServer.start_link(__MODULE__, config, opts)
  end

  @doc """
  Registers the worker with the LiveKit server.
  """
  @spec register_worker(pid()) :: :ok | {:error, term()}
  def register_worker(worker_pid) do
    GenServer.call(worker_pid, :register_worker, 15_000)
  end

  @doc """
  Unregisters the worker from the LiveKit server.
  """
  @spec unregister_worker(pid()) :: :ok
  def unregister_worker(worker_pid) do
    GenServer.call(worker_pid, :unregister_worker)
  end

  @doc """
  Gets current worker status and metrics.
  """
  @spec get_status(pid()) :: map()
  def get_status(worker_pid) do
    GenServer.call(worker_pid, :get_status)
  end

  @doc """
  Gets list of active jobs.
  """
  @spec list_active_jobs(pid()) :: list()
  def list_active_jobs(worker_pid) do
    GenServer.call(worker_pid, :list_active_jobs)
  end

  @doc """
  Terminates a specific job.
  """
  @spec terminate_job(pid(), String.t()) :: :ok | {:error, term()}
  def terminate_job(worker_pid, job_id) do
    GenServer.call(worker_pid, {:terminate_job, job_id})
  end

  @doc """
  Updates worker configuration at runtime.
  """
  @spec update_config(pid(), map()) :: :ok | {:error, term()}
  def update_config(worker_pid, config_updates) do
    GenServer.call(worker_pid, {:update_config, config_updates})
  end

  # GenServer Callbacks

  @impl true
  def init(config) do
    Logger.info("Starting LiveKit Agent Worker: #{config.worker_id}")

    # Validate configuration
    case validate_config(config) do
      :ok ->
        state = %State{
          config: config,
          metrics: Map.put(%{}, :worker_start_time, DateTime.utc_now())
        }

        # Schedule health checks
        schedule_health_check(config.health_check_interval)

        # Auto-register if we have credentials
        if config.api_key && config.api_secret do
          send(self(), :auto_register)
        end

        {:ok, state}

      {:error, reason} ->
        Logger.error("Invalid worker configuration: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:register_worker, _from, state) do
    case register_with_server(state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:unregister_worker, _from, state) do
    new_state = unregister_from_server(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      worker_id: state.config.worker_id,
      registered: state.registered,
      health_status: state.health_status,
      active_jobs: map_size(state.active_jobs),
      max_concurrent_jobs: state.config.max_concurrent_jobs,
      last_heartbeat: state.last_heartbeat,
      metrics: state.metrics,
      uptime_seconds: calculate_uptime(state.metrics.worker_start_time)
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:list_active_jobs, _from, state) do
    jobs = Enum.map(state.active_jobs, fn {job_id, job_info} ->
      %{
        job_id: job_id,
        room_name: job_info.room_name,
        started_at: job_info.started_at,
        participant_identity: job_info.participant_identity,
        status: job_info.status
      }
    end)

    {:reply, jobs, state}
  end

  @impl true
  def handle_call({:terminate_job, job_id}, _from, state) do
    case Map.get(state.active_jobs, job_id) do
      nil ->
        {:reply, {:error, :job_not_found}, state}

      job_info ->
        # Terminate the job session
        if job_info.session_pid && Process.alive?(job_info.session_pid) do
          GenServer.stop(job_info.session_pid, :normal, 5_000)
        end

        new_active_jobs = Map.delete(state.active_jobs, job_id)
        new_state = %{state | active_jobs: new_active_jobs}

        Logger.info("Terminated job: #{job_id}")
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:update_config, config_updates}, _from, state) do
    case update_worker_config(state.config, config_updates) do
      {:ok, new_config} ->
        new_state = %{state | config: new_config}
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:job_request, job_request}, state) do
    new_state = handle_job_request(state, job_request)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:auto_register, state) do
    case register_with_server(state) do
      {:ok, new_state} ->
        Logger.info("Worker auto-registered successfully")
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Worker auto-registration failed: #{inspect(reason)}")
        # Retry after delay
        Process.send_after(self(), :auto_register, 10_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:health_check, state) do
    new_state = perform_health_check(state)
    schedule_health_check(state.config.health_check_interval)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:job_completed, job_id, result}, state) do
    new_state = handle_job_completion(state, job_id, result)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:job_failed, job_id, reason}, state) do
    new_state = handle_job_failure(state, job_id, reason)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Handle monitored process (job session) going down
    case find_job_by_pid(state.active_jobs, pid) do
      {job_id, _job_info} ->
        Logger.warn("Job session #{job_id} process went down: #{inspect(reason)}")
        new_active_jobs = Map.delete(state.active_jobs, job_id)

        new_metrics = state.metrics
                     |> Map.update!(:jobs_failed, &(&1 + 1))

        new_state = %{state | active_jobs: new_active_jobs, metrics: new_metrics}
        {:noreply, new_state}

      nil ->
        Logger.debug("Unknown monitored process went down: #{inspect(pid)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Worker received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Worker terminating: #{inspect(reason)}")

    # Unregister from server
    unregister_from_server(state)

    # Terminate all active jobs
    Enum.each(state.active_jobs, fn {_job_id, job_info} ->
      if job_info.session_pid && Process.alive?(job_info.session_pid) do
        GenServer.stop(job_info.session_pid, :shutdown, 5_000)
      end
    end)

    :ok
  end

  # Private Functions

  defp validate_config(config) do
    cond do
      is_nil(config.api_key) ->
        {:error, :missing_api_key}

      is_nil(config.api_secret) ->
        {:error, :missing_api_secret}

      is_nil(config.entrypoint) ->
        {:error, :missing_entrypoint_function}

      config.max_concurrent_jobs <= 0 ->
        {:error, :invalid_max_concurrent_jobs}

      true ->
        :ok
    end
  end

  defp generate_worker_id do
    "elixir-worker-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end

  defp register_with_server(state) do
    try do
      Logger.info("Registering worker with LiveKit server: #{state.config.server_url}")

      # In a real implementation, this would establish WebSocket connection
      # and send worker registration message
      # For now, we'll simulate successful registration

      new_state = %{state |
        registered: true,
        last_heartbeat: DateTime.utc_now(),
        connection: :mock_connection
      }

      {:ok, new_state}
    rescue
      error ->
        Logger.error("Worker registration failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp unregister_from_server(state) do
    if state.registered do
      Logger.info("Unregistering worker from LiveKit server")
      # Close WebSocket connection and clean up
    end

    %{state | registered: false, connection: nil}
  end

  defp handle_job_request(state, job_request) do
    if map_size(state.active_jobs) >= state.config.max_concurrent_jobs do
      Logger.warn("Rejecting job request - worker at capacity")
      # Send rejection response
      state
    else
      Logger.info("Processing job request for room: #{job_request.room_name}")

      case start_job_session(state, job_request) do
        {:ok, session_pid, job_info} ->
          new_active_jobs = Map.put(state.active_jobs, job_request.job_id, job_info)

          new_metrics = state.metrics
                       |> Map.update!(:jobs_processed, &(&1 + 1))
                       |> Map.put(:last_job_at, DateTime.utc_now())

          %{state | active_jobs: new_active_jobs, metrics: new_metrics}

        {:error, reason} ->
          Logger.error("Failed to start job session: #{inspect(reason)}")

          new_metrics = Map.update!(state.metrics, :jobs_failed, &(&1 + 1))
          %{state | metrics: new_metrics}
      end
    end
  end

  defp start_job_session(state, job_request) do
    try do
      # Create job context
      job_context = JobContext.new(%{
        job_id: job_request.job_id,
        room_name: job_request.room_name,
        participant_identity: job_request.participant_identity || "agent",
        server_url: state.config.server_url,
        api_key: state.config.api_key,
        api_secret: state.config.api_secret,
        metadata: job_request.metadata || %{}
      })

      # Start agent session
      session_config = %AgentSession.Config{
        room_name: job_request.room_name,
        participant_identity: job_request.participant_identity || "agent",
        server_url: state.config.server_url,
        api_key: state.config.api_key,
        api_secret: state.config.api_secret,
        voice_agent_config: create_default_voice_agent_config()
      }

      case AgentSession.start_link(session_config) do
        {:ok, session_pid} ->
          # Monitor the session
          Process.monitor(session_pid)

          # Call the entrypoint function
          spawn_link(fn ->
            try do
              result = state.config.entrypoint.(job_context)
              send(self(), {:job_completed, job_request.job_id, result})
            rescue
              error ->
                send(self(), {:job_failed, job_request.job_id, error})
            end
          end)

          job_info = %{
            session_pid: session_pid,
            room_name: job_request.room_name,
            participant_identity: job_request.participant_identity,
            started_at: DateTime.utc_now(),
            status: :running
          }

          {:ok, session_pid, job_info}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        {:error, error}
    end
  end

  defp create_default_voice_agent_config do
    %VoiceAgent.Config{
      instructions: "You are a helpful AI assistant.",
      name: "Agent",
      stt: nil,  # Will be configured when AI providers are implemented
      llm: nil,
      tts: nil
    }
  end

  defp handle_job_completion(state, job_id, result) do
    Logger.info("Job #{job_id} completed: #{inspect(result)}")

    case Map.get(state.active_jobs, job_id) do
      nil ->
        state

      job_info ->
        # Calculate job duration
        duration = DateTime.diff(DateTime.utc_now(), job_info.started_at, :millisecond)

        new_active_jobs = Map.delete(state.active_jobs, job_id)

        new_metrics = state.metrics
                     |> update_avg_job_duration(duration)

        %{state | active_jobs: new_active_jobs, metrics: new_metrics}
    end
  end

  defp handle_job_failure(state, job_id, reason) do
    Logger.error("Job #{job_id} failed: #{inspect(reason)}")

    new_active_jobs = Map.delete(state.active_jobs, job_id)

    new_metrics = Map.update!(state.metrics, :jobs_failed, &(&1 + 1))

    %{state | active_jobs: new_active_jobs, metrics: new_metrics}
  end

  defp perform_health_check(state) do
    # Check system health
    health_status = check_system_health(state)

    # Send heartbeat if registered
    if state.registered do
      send_heartbeat(state)
    end

    %{state |
      health_status: health_status,
      last_heartbeat: DateTime.utc_now()
    }
  end

  defp check_system_health(state) do
    active_job_count = map_size(state.active_jobs)
    max_jobs = state.config.max_concurrent_jobs

    load_percentage = active_job_count / max_jobs

    cond do
      load_percentage < 0.7 -> :healthy
      load_percentage < 0.9 -> :degraded
      true -> :unhealthy
    end
  end

  defp send_heartbeat(_state) do
    # In real implementation, send heartbeat to LiveKit server
    Logger.debug("Sending worker heartbeat")
  end

  defp schedule_health_check(interval) do
    Process.send_after(self(), :health_check, interval)
  end

  defp find_job_by_pid(active_jobs, pid) do
    Enum.find(active_jobs, fn {_job_id, job_info} ->
      job_info.session_pid == pid
    end)
  end

  defp update_worker_config(current_config, updates) do
    try do
      new_config = struct(current_config, updates)
      {:ok, new_config}
    rescue
      error ->
        {:error, error}
    end
  end

  defp calculate_uptime(start_time) do
    DateTime.diff(DateTime.utc_now(), start_time, :second)
  end

  defp update_avg_job_duration(metrics, new_duration) do
    current_avg = Map.get(metrics, :avg_job_duration, 0)
    job_count = Map.get(metrics, :jobs_processed, 1)

    new_avg = (current_avg * (job_count - 1) + new_duration) / job_count

    Map.put(metrics, :avg_job_duration, new_avg)
  end
end
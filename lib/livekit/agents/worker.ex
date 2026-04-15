defmodule Livekit.Agents.Worker do
  @moduledoc """
  GenServer that manages the connection between this Elixir agent process and
  the LiveKit server.

  Responsibilities:
  - Opens a Gun WebSocket connection to the LiveKit server and completes the
    register handshake using the real LiveKit protobuf wire protocol.
  - Sends periodic ping/status updates carrying current load information.
  - Responds to `AvailabilityRequest` messages by accepting or rejecting new
    jobs based on capacity and drain state.
  - On job assignment (`JobAssignment`), spawns an `AgentSession` under
    `JobSupervisor` and monitors it for lifecycle management.
  - Implements graceful drain: stops accepting new jobs and waits (up to
    `drain_timeout` ms) for in-flight sessions to finish.
  - Reports load as `active_jobs / max_concurrent_jobs` in every status update.

  ## Wire Protocol

  The LiveKit agent worker protocol uses protobuf binary frames over WebSocket.

  Worker -> Server: `Livekit.WorkerMessage` (oneof: register, availability,
  update_worker, update_job, ping)

  Server -> Worker: `Livekit.ServerMessage` (oneof: register, availability,
  assignment, pong, termination)

  ## Mock mode

  When `server_url` is `nil` or starts with `"mock://"`, the Worker operates
  in mock mode: it skips all Gun calls, immediately marks itself as registered,
  and logs heartbeats instead of sending them over the wire. This is the
  default behaviour when no server is configured, making it safe for testing.

  ## Usage

      {:ok, pid} = Worker.start_link(%Worker.Config{
        api_key: "key",
        api_secret: "secret",
        entrypoint: &MyAgent.run/1
      })

      :ok = Worker.drain(pid)
  """

  use GenServer
  require Logger

  alias Livekit.Agents.{AgentSession, JobSupervisor}

  alias Livekit.{
    AvailabilityResponse,
    JobType,
    RegisterWorkerRequest,
    ServerMessage,
    UpdateJobStatus,
    UpdateWorkerStatus,
    WorkerMessage,
    WorkerPing,
    WorkerStatus
  }

  # SDK version reported during registration
  @sdk_version "0.1.4"

  # Heartbeat ping interval sent to the server (ms)
  @ping_interval_ms 5_000

  # ---------------------------------------------------------------------------
  # Config
  # ---------------------------------------------------------------------------

  defmodule Config do
    @moduledoc """
    Configuration for `Livekit.Agents.Worker`.

    ## Fields

    - `worker_id` — unique identifier for this worker; generated if `nil`
    - `server_url` — WebSocket URL of the LiveKit server (`ws://` or `wss://`);
      set to `nil` or `"mock://..."` to run in mock mode
    - `api_key` — LiveKit API key (required)
    - `api_secret` — LiveKit API secret (required)
    - `entrypoint` — function called with a `JobContext.t()` to run the agent
      (required)
    - `max_concurrent_jobs` — maximum number of simultaneous job sessions
      (default `10`)
    - `heartbeat_interval` — milliseconds between heartbeat/status-update
      messages (default `30_000`)
    - `namespace` — agent namespace used during registration (default
      `"default"`)
    - `agent_name` — human-readable name for this worker (default
      `"elixir-agent"`)
    - `drain_timeout` — milliseconds to wait for in-flight jobs during drain
      before giving up (default `60_000`)
    - `worker_metadata` — arbitrary metadata map included in registration
    """

    @type entrypoint_fn :: (map() -> :ok | {:error, term()})

    @type t :: %__MODULE__{
            worker_id: String.t() | nil,
            server_url: String.t() | nil,
            api_key: String.t() | nil,
            api_secret: String.t() | nil,
            entrypoint: entrypoint_fn() | nil,
            max_concurrent_jobs: pos_integer(),
            heartbeat_interval: pos_integer(),
            namespace: String.t(),
            agent_name: String.t(),
            drain_timeout: pos_integer(),
            worker_metadata: map()
          }

    defstruct [
      :worker_id,
      :api_key,
      :api_secret,
      :entrypoint,
      server_url: nil,
      max_concurrent_jobs: 10,
      heartbeat_interval: 30_000,
      namespace: "default",
      agent_name: "elixir-agent",
      drain_timeout: 60_000,
      worker_metadata: %{}
    ]
  end

  # ---------------------------------------------------------------------------
  # State
  # ---------------------------------------------------------------------------

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            config: Config.t(),
            gun_pid: pid() | nil,
            gun_monitor: reference() | nil,
            ws_stream: reference() | nil,
            registered: boolean(),
            server_worker_id: String.t() | nil,
            active_jobs: map(),
            health_status: :healthy | :degraded | :unhealthy,
            last_heartbeat: DateTime.t() | nil,
            backoff_ms: pos_integer(),
            draining: boolean(),
            drain_from: GenServer.from() | nil,
            metrics: map()
          }

    defstruct [
      :config,
      :gun_pid,
      :gun_monitor,
      :ws_stream,
      :drain_from,
      :server_worker_id,
      registered: false,
      active_jobs: %{},
      health_status: :healthy,
      last_heartbeat: nil,
      backoff_ms: 1_000,
      draining: false,
      metrics: %{
        jobs_processed: 0,
        jobs_failed: 0,
        worker_start_time: nil
      }
    ]
  end

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @doc """
  Starts a Worker with the given configuration and GenServer options.

  Accepts a 2-tuple `{config, opts}` so it can be used directly as a
  Supervisor child spec. The `config.worker_id` is auto-generated when `nil`.
  """
  @spec start_link({Config.t(), GenServer.options()}) :: GenServer.on_start()
  def start_link({config, opts}) do
    config = %{config | worker_id: config.worker_id || generate_worker_id()}
    GenServer.start_link(__MODULE__, config, opts)
  end

  @doc """
  Starts a Worker when passing config and opts separately (convenience form).
  """
  @spec start_link(Config.t(), GenServer.options()) :: GenServer.on_start()
  def start_link(config, opts \\ []) do
    start_link({config, opts})
  end

  @doc """
  Initiates graceful drain: stops accepting new jobs and waits up to 90 s for
  in-flight sessions to finish. Returns `:ok` when all jobs have completed or
  `{:error, :timeout}` if `drain_timeout` is exceeded.
  """
  @spec drain(pid() | atom()) :: :ok | {:error, :timeout}
  def drain(worker_pid) do
    GenServer.call(worker_pid, :drain, 90_000)
  end

  @doc """
  Returns current worker status as a map including load, drain state, and
  metrics.
  """
  @spec get_status(pid() | atom()) :: map()
  def get_status(worker_pid) do
    GenServer.call(worker_pid, :get_status, 5_000)
  end

  @doc """
  Returns a list of maps describing each active job session.
  """
  @spec list_active_jobs(pid() | atom()) :: list()
  def list_active_jobs(worker_pid) do
    GenServer.call(worker_pid, :list_active_jobs, 5_000)
  end

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(config) do
    Logger.info("Starting LiveKit Agent Worker: #{config.worker_id}")

    case validate_config(config) do
      :ok ->
        state = %State{
          config: config,
          metrics: %{jobs_processed: 0, jobs_failed: 0, worker_start_time: DateTime.utc_now()}
        }

        send(self(), :connect)
        {:ok, state}

      {:error, reason} ->
        Logger.error("Invalid worker configuration: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  # ISSUE-06: Guard against double-drain blocking the first caller
  @impl true
  def handle_call(:drain, _from, %{draining: true} = state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:drain, from, state) do
    Logger.info("Worker drain initiated, active_jobs=#{map_size(state.active_jobs)}")

    new_state = %{state | draining: true, drain_from: from}

    if state.registered and not mock_mode?(state.config) do
      send_update_worker_status(state, :WS_FULL)
    end

    if map_size(state.active_jobs) == 0 do
      Process.send_after(self(), :stop_after_drain, 0)
      {:reply, :ok, new_state}
    else
      Process.send_after(self(), :drain_timeout, state.config.drain_timeout)
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    active = map_size(state.active_jobs)
    max = state.config.max_concurrent_jobs
    load = if max > 0, do: active / max, else: 0.0

    status = %{
      worker_id: state.config.worker_id,
      server_worker_id: state.server_worker_id,
      registered: state.registered,
      health_status: state.health_status,
      active_jobs: active,
      max_concurrent_jobs: max,
      load: load,
      last_heartbeat: state.last_heartbeat,
      draining: state.draining,
      namespace: state.config.namespace,
      metrics: state.metrics
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:list_active_jobs, _from, state) do
    jobs =
      Enum.map(state.active_jobs, fn {job_id, info} ->
        %{
          job_id: job_id,
          room_name: info.room_name,
          started_at: info.started_at,
          participant_identity: info.participant_identity
        }
      end)

    {:reply, jobs, state}
  end

  # --- Connection flow -------------------------------------------------------

  @impl true
  def handle_info(:connect, state) do
    if mock_mode?(state.config) do
      Logger.info("Worker #{state.config.worker_id} running in mock mode (no server_url)")
      new_state = %{state | registered: true}
      schedule_heartbeat(new_state)
      {:noreply, new_state}
    else
      case connect_to_server(state) do
        {:ok, new_state} ->
          {:noreply, new_state}

        {:error, reason} ->
          Logger.warning(
            "Worker connection failed: #{inspect(reason)}, retrying in #{state.backoff_ms} ms"
          )

          Process.send_after(self(), :connect, state.backoff_ms)
          {:noreply, %{state | backoff_ms: next_backoff(state.backoff_ms)}}
      end
    end
  end

  @impl true
  def handle_info({:gun_up, gun_pid, :http}, %State{gun_pid: gun_pid} = state) do
    Logger.debug("Gun HTTP connection up, upgrading to WebSocket")

    token = build_auth_token(state.config)

    stream =
      :gun.ws_upgrade(gun_pid, "/agent", [
        {"authorization", "Bearer #{token}"},
        {"x-livekit-worker-id", state.config.worker_id}
      ])

    {:noreply, %{state | ws_stream: stream}}
  end

  @impl true
  def handle_info({:gun_upgrade, _gun_pid, _stream, ["websocket"], _headers}, state) do
    Logger.info("Worker WebSocket upgraded, sending RegisterWorkerRequest")

    ping_interval_s = div(@ping_interval_ms, 1_000)

    register_req = %RegisterWorkerRequest{
      type: JobType.value(:JT_ROOM),
      agent_name: state.config.agent_name,
      version: @sdk_version,
      ping_interval: ping_interval_s,
      namespace: state.config.namespace
    }

    send_worker_message(state, {:register, register_req})
    new_state = %{state | registered: true, backoff_ms: 1_000}
    schedule_heartbeat(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:gun_ws, _gun_pid, _stream, {:binary, data}}, state) do
    case decode_server_message(data) do
      {:ok, {type, payload}} ->
        new_state = dispatch_server_message(type, payload, state)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("Failed to decode server protobuf message: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  # Legacy text-frame handler kept for compatibility during transition
  @impl true
  def handle_info({:gun_ws, _gun_pid, _stream, {:text, _data}}, state) do
    Logger.debug("Received unexpected text frame from server (expected binary protobuf)")
    {:noreply, state}
  end

  @impl true
  def handle_info({:gun_down, _pid, _proto, reason, _}, state) do
    Logger.warning("Gun WebSocket connection down: #{inspect(reason)}")
    new_state = clear_connection(state)
    Process.send_after(self(), :connect, new_state.backoff_ms)
    {:noreply, %{new_state | backoff_ms: next_backoff(new_state.backoff_ms)}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %State{gun_monitor: ref} = state) do
    Logger.warning("Gun process went down: #{inspect(reason)}")
    new_state = clear_connection(state)
    Process.send_after(self(), :connect, new_state.backoff_ms)
    {:noreply, %{new_state | backoff_ms: next_backoff(new_state.backoff_ms)}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case find_job_by_monitor(state.active_jobs, ref) do
      {job_id, _info} ->
        Logger.info("Job session #{job_id} (pid=#{inspect(pid)}) ended: #{inspect(reason)}")
        maybe_send_job_status(state, job_id, reason)

        new_active = Map.delete(state.active_jobs, job_id)
        new_metrics = Map.update!(state.metrics, :jobs_processed, &(&1 + 1))
        new_state = %{state | active_jobs: new_active, metrics: new_metrics}
        handle_job_ended(new_state, new_active)

      nil ->
        Logger.debug("Unknown monitored process went down: #{inspect(pid)}")
        {:noreply, state}
    end
  end

  # --- Heartbeat ------------------------------------------------------------

  @impl true
  def handle_info(:heartbeat, state) do
    active = map_size(state.active_jobs)
    max = state.config.max_concurrent_jobs
    load = if max > 0, do: active / max, else: 0.0

    if mock_mode?(state.config) do
      Logger.debug("Worker heartbeat (mock): load=#{Float.round(load, 2)}, jobs=#{active}/#{max}")
    else
      send_ping(state)
      send_worker_load_update(state)
    end

    new_state = %{state | last_heartbeat: DateTime.utc_now(), health_status: compute_health(load)}

    unless state.draining and active == 0 do
      schedule_heartbeat(new_state)
    end

    {:noreply, new_state}
  end

  # --- Drain helpers --------------------------------------------------------

  @impl true
  def handle_info(:drain_timeout, %State{draining: true} = state) do
    Logger.warning(
      "Worker drain timed out with #{map_size(state.active_jobs)} jobs still running"
    )

    if state.drain_from do
      GenServer.reply(state.drain_from, {:error, :timeout})
    end

    {:stop, :normal, %{state | drain_from: nil}}
  end

  @impl true
  def handle_info(:drain_timeout, state), do: {:noreply, state}

  @impl true
  def handle_info(:stop_after_drain, state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Worker received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Worker terminating: #{inspect(reason)}")

    if state.gun_pid && Process.alive?(state.gun_pid) do
      :gun.close(state.gun_pid)
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp validate_config(config) do
    cond do
      is_nil(config.api_key) -> {:error, :missing_api_key}
      is_nil(config.api_secret) -> {:error, :missing_api_secret}
      is_nil(config.entrypoint) -> {:error, :missing_entrypoint_function}
      config.max_concurrent_jobs <= 0 -> {:error, :invalid_max_concurrent_jobs}
      true -> :ok
    end
  end

  defp generate_worker_id do
    "elixir-worker-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end

  defp mock_mode?(config) do
    is_nil(config.server_url) or String.starts_with?(config.server_url, "mock://")
  end

  defp connect_to_server(state) do
    uri = URI.parse(state.config.server_url)
    host = String.to_charlist(uri.host || "localhost")
    port = uri.port || default_port(uri.scheme)
    transport = if uri.scheme == "wss", do: :tls, else: :tcp

    opts = %{protocols: [:http], transport: transport}

    case :gun.open(host, port, opts) do
      {:ok, gun_pid} ->
        ref = Process.monitor(gun_pid)
        {:ok, %{state | gun_pid: gun_pid, gun_monitor: ref}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp default_port("wss"), do: 443
  defp default_port(_), do: 80

  defp clear_connection(state) do
    if state.gun_monitor, do: Process.demonitor(state.gun_monitor, [:flush])

    %{
      state
      | gun_pid: nil,
        gun_monitor: nil,
        ws_stream: nil,
        registered: false,
        server_worker_id: nil
    }
  end

  defp next_backoff(current_ms) do
    min(current_ms * 2, 30_000)
  end

  defp schedule_heartbeat(state) do
    Process.send_after(self(), :heartbeat, state.config.heartbeat_interval)
  end

  # Encode a WorkerMessage oneof and send as a binary WebSocket frame
  defp send_worker_message(state, {field, payload}) do
    if state.gun_pid && state.ws_stream do
      msg = %WorkerMessage{message: {field, payload}}
      binary = Protobuf.encode(msg)
      :gun.ws_send(state.gun_pid, state.ws_stream, {:binary, binary})
    end
  end

  defp send_ping(state) do
    ts = System.system_time(:millisecond)
    send_worker_message(state, {:ping, %WorkerPing{timestamp: ts}})
  end

  defp send_worker_load_update(state) do
    active = map_size(state.active_jobs)
    max = state.config.max_concurrent_jobs
    load = if max > 0, do: active / max, else: 0.0

    worker_status =
      if state.draining, do: WorkerStatus.value(:WS_FULL), else: WorkerStatus.value(:WS_AVAILABLE)

    update = %UpdateWorkerStatus{
      status: worker_status,
      load: load,
      job_count: active
    }

    send_worker_message(state, {:update_worker, update})
  end

  defp send_update_worker_status(state, status_atom) do
    worker_status = WorkerStatus.value(status_atom)

    update = %UpdateWorkerStatus{
      status: worker_status,
      load: 0.0,
      job_count: 0
    }

    send_worker_message(state, {:update_worker, update})
  end

  defp send_job_status_update(state, job_id, status_atom) do
    status_val =
      case status_atom do
        :JS_SUCCESS -> 2
        :JS_FAILED -> 3
        _ -> 1
      end

    update = %UpdateJobStatus{
      job_id: job_id,
      status: status_val
    }

    send_worker_message(state, {:update_job, update})
  end

  defp compute_health(load) do
    cond do
      load < 0.7 -> :healthy
      load < 0.9 -> :degraded
      true -> :unhealthy
    end
  end

  defp build_auth_token(config) do
    alias Livekit.AccessToken
    alias Livekit.Grants

    grants = %Grants{room_join: true, room_admin: true}

    AccessToken.new(config.api_key, config.api_secret)
    |> AccessToken.with_identity(config.worker_id)
    |> AccessToken.with_grants(grants)
    |> AccessToken.to_jwt()
  end

  # Safely decode a ServerMessage from binary protobuf data
  defp decode_server_message(data) do
    msg = Protobuf.decode(data, ServerMessage)

    case msg.message do
      {_type, _payload} = result -> {:ok, result}
      nil -> {:error, :empty_message}
    end
  rescue
    error -> {:error, error}
  end

  # --- Server message dispatch -----------------------------------------------

  defp dispatch_server_message(:register, payload, state) do
    server_worker_id = payload.worker_id
    server_version = if payload.server_info, do: payload.server_info.version, else: "unknown"

    Logger.info(
      "Worker registered with server: worker_id=#{server_worker_id}, server_version=#{server_version}"
    )

    new_state = %{state | server_worker_id: server_worker_id}
    send_worker_load_update(new_state)
    new_state
  end

  defp dispatch_server_message(:availability, payload, state) do
    handle_availability_request(payload, state)
  end

  defp dispatch_server_message(:assignment, payload, state) do
    handle_job_assignment(payload, state)
  end

  defp dispatch_server_message(:pong, payload, state) do
    rtt_ms = System.system_time(:millisecond) - payload.last_timestamp
    Logger.debug("Worker received pong: rtt=#{rtt_ms}ms")
    state
  end

  defp dispatch_server_message(:termination, payload, state) do
    Logger.info("Server requested job termination: job_id=#{payload.job_id}")

    case Map.get(state.active_jobs, payload.job_id) do
      %{session_pid: pid} ->
        Process.exit(pid, :server_termination)

      nil ->
        Logger.debug("Termination request for unknown job: #{payload.job_id}")
    end

    state
  end

  defp dispatch_server_message(type, _payload, state) do
    Logger.debug("Worker received unhandled server message type: #{inspect(type)}")
    state
  end

  # --- Availability ----------------------------------------------------------

  defp handle_availability_request(availability_request, state) do
    job = availability_request.job
    job_id = if job, do: job.id, else: ""
    active = map_size(state.active_jobs)
    at_capacity = active >= state.config.max_concurrent_jobs
    available = not state.draining and not at_capacity

    response = %AvailabilityResponse{
      job_id: job_id,
      available: available,
      supports_resume: false,
      participant_identity: state.config.worker_id
    }

    send_worker_message(state, {:availability, response})

    Logger.debug(
      "Availability request for job=#{job_id}: available=#{available}" <>
        " (draining=#{state.draining}, active=#{active}/#{state.config.max_concurrent_jobs})"
    )

    state
  end

  # --- Job assignment --------------------------------------------------------

  defp handle_job_assignment(assignment, state) do
    job = assignment.job

    if is_nil(job) or job.id == "" do
      Logger.warning("Received job assignment with nil or empty job")
      state
    else
      room = job.room
      participant = job.participant

      room_name = if room, do: room.name, else: ""
      participant_identity = if participant, do: participant.identity, else: ""

      session_config = %AgentSession.Config{
        room_name: room_name,
        participant_identity: participant_identity,
        server_url: assignment.url || state.config.server_url,
        api_key: state.config.api_key,
        api_secret: state.config.api_secret
      }

      case JobSupervisor.start_job(session_config) do
        {:ok, session_pid} ->
          monitor_ref = Process.monitor(session_pid)

          job_info = %{
            session_pid: session_pid,
            monitor_ref: monitor_ref,
            room_name: room_name,
            participant_identity: participant_identity,
            started_at: DateTime.utc_now()
          }

          Logger.info(
            "Job assigned: id=#{job.id}, room=#{room_name}, participant=#{participant_identity}"
          )

          new_state = %{state | active_jobs: Map.put(state.active_jobs, job.id, job_info)}
          send_worker_load_update(new_state)
          new_state

        {:error, reason} ->
          Logger.error("Failed to start job session for job=#{job.id}: #{inspect(reason)}")
          send_job_status_update(state, job.id, :JS_FAILED)
          %{state | metrics: Map.update!(state.metrics, :jobs_failed, &(&1 + 1))}
      end
    end
  end

  defp find_job_by_monitor(active_jobs, ref) do
    Enum.find(active_jobs, fn {_job_id, info} ->
      info.monitor_ref == ref
    end)
  end

  defp maybe_send_job_status(state, job_id, reason) do
    if state.gun_pid do
      status = if reason == :normal, do: :JS_SUCCESS, else: :JS_FAILED
      send_job_status_update(state, job_id, status)
    end
  end

  defp handle_job_ended(new_state, new_active) do
    if new_state.draining and map_size(new_active) == 0 do
      GenServer.reply(new_state.drain_from, :ok)
      {:stop, :normal, %{new_state | drain_from: nil}}
    else
      send_worker_load_update(new_state)
      {:noreply, new_state}
    end
  end
end

defmodule Livekit.Agents.Worker do
  @moduledoc """
  GenServer that manages the connection between this Elixir agent process and
  the LiveKit server.

  Responsibilities:
  - Opens a Gun WebSocket connection to the LiveKit server and completes the
    register handshake.
  - Sends periodic heartbeats (KeepAlive) carrying current load information.
  - Responds to `availability_request` messages by accepting or rejecting new
    jobs based on capacity and drain state.
  - On job assignment, spawns an `AgentSession` under `JobSupervisor` and
    monitors it for lifecycle management.
  - Implements graceful drain: stops accepting new jobs and waits (up to
    `drain_timeout` ms) for in-flight sessions to finish.
  - Reports load as `active_jobs / max_concurrent_jobs` in every heartbeat.

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
    - `heartbeat_interval` — milliseconds between heartbeat messages
      (default `30_000`)
    - `namespace` — agent namespace used during registration (default
      `"default"`)
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

  @impl true
  def handle_call(:drain, from, state) do
    Logger.info("Worker drain initiated, active_jobs=#{map_size(state.active_jobs)}")

    new_state = %{state | draining: true, drain_from: from}

    if state.registered and not mock_mode?(state.config) do
      send_ws_message(state, %{type: "deregister"})
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
          Logger.warning("Worker connection failed: #{inspect(reason)}, retrying in #{state.backoff_ms} ms")
          Process.send_after(self(), :connect, state.backoff_ms)
          {:noreply, %{state | backoff_ms: next_backoff(state.backoff_ms)}}
      end
    end
  end

  @impl true
  def handle_info({:gun_up, gun_pid, :http}, %State{gun_pid: gun_pid} = state) do
    Logger.debug("Gun HTTP connection up, upgrading to WebSocket")

    stream =
      :gun.ws_upgrade(gun_pid, "/agent", [
        {"x-livekit-worker-id", state.config.worker_id}
      ])

    {:noreply, %{state | ws_stream: stream}}
  end

  @impl true
  def handle_info({:gun_upgrade, _gun_pid, _stream, ["websocket"], _headers}, state) do
    Logger.info("Worker WebSocket upgraded, sending register")

    msg = %{
      type: "register",
      worker_id: state.config.worker_id,
      max_concurrent_jobs: state.config.max_concurrent_jobs,
      load: 0.0,
      namespace: state.config.namespace
    }

    send_ws_message(state, msg)
    new_state = %{state | registered: true, backoff_ms: 1_000}
    schedule_heartbeat(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:gun_ws, _gun_pid, _stream, {:text, data}}, state) do
    case Jason.decode(data) do
      {:ok, %{"type" => msg_type} = payload} ->
        new_state = dispatch_server_message(msg_type, payload, state)
        {:noreply, new_state}

      {:ok, _payload} ->
        Logger.debug("Received server message without type field")
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Failed to decode server message: #{inspect(reason)}")
        {:noreply, state}
    end
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
        new_active = Map.delete(state.active_jobs, job_id)
        new_metrics = Map.update!(state.metrics, :jobs_processed, &(&1 + 1))
        new_state = %{state | active_jobs: new_active, metrics: new_metrics}

        if state.draining and map_size(new_active) == 0 do
          GenServer.reply(state.drain_from, :ok)
          {:stop, :normal, %{new_state | drain_from: nil}}
        else
          {:noreply, new_state}
        end

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
      send_ws_message(state, %{type: "keepalive", load: load})
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
    Logger.warning("Worker drain timed out with #{map_size(state.active_jobs)} jobs still running")

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

    %{state |
      gun_pid: nil,
      gun_monitor: nil,
      ws_stream: nil,
      registered: false
    }
  end

  defp next_backoff(current_ms) do
    min(current_ms * 2, 30_000)
  end

  defp schedule_heartbeat(state) do
    Process.send_after(self(), :heartbeat, state.config.heartbeat_interval)
  end

  defp send_ws_message(state, msg) do
    if state.gun_pid && state.ws_stream do
      :gun.ws_send(state.gun_pid, state.ws_stream, {:text, Jason.encode!(msg)})
    end
  end

  defp compute_health(load) do
    cond do
      load < 0.7 -> :healthy
      load < 0.9 -> :degraded
      true -> :unhealthy
    end
  end

  # --- Server message dispatch -----------------------------------------------

  defp dispatch_server_message("register_response", payload, state) do
    server_version = Map.get(payload, "server_version", "unknown")
    Logger.info("Worker registered with server (version: #{server_version})")
    state
  end

  defp dispatch_server_message("availability_request", payload, state) do
    handle_availability_request(payload, state)
  end

  defp dispatch_server_message("job_assignment", payload, state) do
    handle_job_assignment(payload, state)
  end

  defp dispatch_server_message(type, _payload, state) do
    Logger.debug("Worker received unhandled server message type: #{type}")
    state
  end

  # --- Availability ----------------------------------------------------------

  defp handle_availability_request(payload, state) do
    job_id = Map.get(payload, "job_id", "")
    active = map_size(state.active_jobs)
    at_capacity = active >= state.config.max_concurrent_jobs
    available = not state.draining and not at_capacity

    response = %{type: "availability_response", job_id: job_id, available: available}
    send_ws_message(state, response)

    Logger.debug("Availability request for job=#{job_id}: available=#{available} (draining=#{state.draining}, active=#{active}/#{state.config.max_concurrent_jobs})")
    state
  end

  # --- Job assignment --------------------------------------------------------

  defp handle_job_assignment(payload, state) do
    with {:ok, job_id} <- require_string_field(payload, "job_id"),
         {:ok, room_name} <- require_string_field(payload, "room_name"),
         {:ok, participant_identity} <- require_string_field(payload, "participant_identity") do
      session_config = %AgentSession.Config{
        room_name: room_name,
        participant_identity: participant_identity,
        server_url: state.config.server_url,
        api_key: state.config.api_key,
        api_secret: state.config.api_secret,
        voice_agent_config: nil
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

          Logger.info("Job assigned: id=#{job_id}, room=#{room_name}, participant=#{participant_identity}")
          %{state | active_jobs: Map.put(state.active_jobs, job_id, job_info)}

        {:error, reason} ->
          Logger.error("Failed to start job session for job=#{job_id}: #{inspect(reason)}")
          %{state | metrics: Map.update!(state.metrics, :jobs_failed, &(&1 + 1))}
      end
    else
      {:error, reason} ->
        Logger.warning("Rejecting malformed job_assignment payload: #{inspect(reason)}")
        state
    end
  end

  defp require_string_field(map, field) do
    case Map.get(map, field) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      nil -> {:error, {:missing_field, field}}
      "" -> {:error, {:empty_field, field}}
      other -> {:error, {:invalid_field, field, other}}
    end
  end

  defp find_job_by_monitor(active_jobs, ref) do
    Enum.find(active_jobs, fn {_job_id, info} ->
      info.monitor_ref == ref
    end)
  end
end

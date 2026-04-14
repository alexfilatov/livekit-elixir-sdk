defmodule Livekit.Agents.AgentSession do
  @moduledoc """
  Orchestrates a LiveKit agent session: Room + Pipeline + RoomIO lifecycle.

  `AgentSession` manages the full lifecycle of an agent connecting to a LiveKit room:

  ## Real mode (`:server_url` present)

  When `config.server_url` is non-nil and non-empty, `connect_to_room/1` will:

  1. Build a JWT access token from the provided `api_key` / `api_secret`.
  2. Connect a `Livekit.WebRTC.Room` to the server.
  3. Start a `Livekit.Agents.Pipeline` with the supplied `pipeline_config`.
  4. Start a `Livekit.Agents.RoomIO` bridging the Room and Pipeline together.

  Audio flows: Room → RoomIO → Pipeline → RoomIO → Room.

  ## Mock mode (`:server_url` nil or empty)

  When no `server_url` is provided the session enters a lightweight simulation
  mode used for development and testing. A background process sends synthetic
  participant events so downstream code can be exercised without a real LiveKit
  server.

  ## Usage

      config = %AgentSession.Config{
        room_name: "my-room",
        participant_identity: "agent",
        server_url: "wss://my-room.livekit.cloud",
        api_key: "key",
        api_secret: "secret",
        pipeline_config: %Pipeline.Config{stt: ..., llm: ..., tts: ...}
      }
      {:ok, pid} = AgentSession.start_link(config)
      :ok = AgentSession.connect_to_room(pid)
  """

  use GenServer
  require Logger

  alias Livekit.WebRTC.Room
  alias Livekit.Agents.{AudioFrame, Pipeline, RoomIO}
  alias Livekit.{AccessToken, Grants}

  # ---------------------------------------------------------------------------
  # Config struct
  # ---------------------------------------------------------------------------

  defmodule Config do
    @moduledoc """
    Configuration for `Livekit.Agents.AgentSession`.

    ## Fields

    - `:room_name` — LiveKit room name to join.
    - `:participant_identity` — Identity published by the agent participant.
    - `:server_url` — LiveKit server WebSocket URL (`"wss://..."`). Set `nil` to use mock mode.
    - `:api_key` — LiveKit API key (required for real mode).
    - `:api_secret` — LiveKit API secret (required for real mode).
    - `:pipeline_config` — `%Pipeline.Config{}` for STT/LLM/TTS. Required for real mode.
    - `:auto_subscribe` — Whether to auto-subscribe to tracks (default `true`).
    - `:nif_module` — NIF implementation to use when creating `Room.Config`. Defaults to
      `Livekit.WebRTC.Native`. Override with a mock module in tests.
    """

    @type t :: %__MODULE__{
            room_name: String.t() | nil,
            participant_identity: String.t() | nil,
            server_url: String.t() | nil,
            api_key: String.t() | nil,
            api_secret: String.t() | nil,
            pipeline_config: Pipeline.Config.t() | nil,
            auto_subscribe: boolean(),
            nif_module: module()
          }

    defstruct [
      :room_name,
      :participant_identity,
      :server_url,
      :api_key,
      :api_secret,
      :pipeline_config,
      auto_subscribe: true,
      nif_module: Livekit.WebRTC.Native
    ]
  end

  # ---------------------------------------------------------------------------
  # State struct
  # ---------------------------------------------------------------------------

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            config: Config.t(),
            room_pid: pid() | nil,
            pipeline_pid: pid() | nil,
            room_io_pid: pid() | nil,
            room_connected: boolean(),
            participants: map(),
            metrics: map()
          }

    defstruct [
      :config,
      :room_pid,
      :pipeline_pid,
      :room_io_pid,
      room_connected: false,
      participants: %{},
      metrics: %{
        session_start: nil,
        participants_joined: 0,
        participants_left: 0
      }
    ]
  end

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @doc """
  Starts an `AgentSession` GenServer linked to the calling process.

  If `config.room_name` is set, an `:auto_connect` message is sent to self
  immediately so the session will attempt to connect to the room on init.
  """
  @spec start_link(Config.t(), GenServer.options()) :: GenServer.on_start()
  def start_link(config, opts \\ []) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  @doc """
  Connects the session to the configured room.

  In real mode starts Room, Pipeline, and RoomIO. In mock mode starts a
  lightweight simulation loop. Returns `:ok` or `{:error, reason}`.
  """
  @spec connect_to_room(pid()) :: :ok | {:error, term()}
  def connect_to_room(session_pid) do
    GenServer.call(session_pid, :connect_to_room, 15_000)
  end

  @doc """
  Disconnects from the current room and stops all supervised children
  (RoomIO, Pipeline, Room).
  """
  @spec disconnect_from_room(pid()) :: :ok
  def disconnect_from_room(session_pid) do
    GenServer.call(session_pid, :disconnect_from_room, 10_000)
  end

  @doc """
  Returns a status map for the current session.

  ## Keys

  - `:room_connected` — `true` when a room connection is active.
  - `:room_name` — room name from config.
  - `:participant_identity` — agent identity from config.
  - `:participants_count` — number of participants currently tracked.
  - `:metrics` — session metrics map (session_start, participants_joined, participants_left).
  """
  @spec get_status(pid()) :: map()
  def get_status(session_pid) do
    GenServer.call(session_pid, :get_status, 5_000)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(config) do
    Logger.info("[AgentSession] Initializing for room: #{config.room_name}")

    metrics = Map.put(%{}, :session_start, DateTime.utc_now())
    metrics = Map.merge(%{participants_joined: 0, participants_left: 0}, metrics)

    state = %State{config: config, metrics: metrics}

    if config.room_name do
      send(self(), :auto_connect)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:connect_to_room, _from, state) do
    case connect_to_room_internal(state) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:disconnect_from_room, _from, state) do
    new_state = disconnect_from_room_internal(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      room_connected: state.room_connected,
      room_name: state.config.room_name,
      participant_identity: state.config.participant_identity,
      participants_count: map_size(state.participants),
      metrics: state.metrics
    }

    {:reply, status, state}
  end

  @impl true
  def handle_cast({:participant_joined, participant_info}, state) do
    Logger.info("[AgentSession] Participant joined: #{participant_info.identity}")
    participants = Map.put(state.participants, participant_info.identity, participant_info)
    metrics = Map.update!(state.metrics, :participants_joined, &(&1 + 1))
    {:noreply, %{state | participants: participants, metrics: metrics}}
  end

  @impl true
  def handle_cast({:participant_left, identity}, state) do
    Logger.info("[AgentSession] Participant left: #{identity}")
    participants = Map.delete(state.participants, identity)
    metrics = Map.update!(state.metrics, :participants_left, &(&1 + 1))
    {:noreply, %{state | participants: participants, metrics: metrics}}
  end

  @impl true
  def handle_info(:auto_connect, state) do
    case connect_to_room_internal(state) do
      {:ok, new_state} ->
        Logger.info("[AgentSession] Auto-connected to room: #{state.config.room_name}")
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("[AgentSession] Auto-connect failed: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  # Room events forwarded in real mode (AgentSession receives them if subscribed)
  @impl true
  def handle_info({:participant_connected, identity}, state) do
    Logger.info("[AgentSession] Participant connected (real): #{identity}")
    participant_info = %{identity: identity, joined_at: DateTime.utc_now()}
    participants = Map.put(state.participants, identity, participant_info)
    metrics = Map.update!(state.metrics, :participants_joined, &(&1 + 1))
    {:noreply, %{state | participants: participants, metrics: metrics}}
  end

  @impl true
  def handle_info({:participant_disconnected, identity}, state) do
    Logger.info("[AgentSession] Participant disconnected (real): #{identity}")
    participants = Map.delete(state.participants, identity)
    metrics = Map.update!(state.metrics, :participants_left, &(&1 + 1))
    {:noreply, %{state | participants: participants, metrics: metrics}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[AgentSession] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("[AgentSession] Terminating: #{inspect(reason)}")
    disconnect_from_room_internal(state)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp real_mode?(%Config{server_url: nil}), do: false
  defp real_mode?(%Config{server_url: ""}), do: false
  defp real_mode?(_config), do: true

  defp connect_to_room_internal(%State{config: config} = state) do
    if real_mode?(config) do
      connect_real(state)
    else
      connect_mock(state)
    end
  end

  defp connect_real(%State{config: config} = state) do
    with {:ok, token} <- build_token(config),
         {:ok, room_pid} <- start_room(config, token),
         {:ok, pipeline_pid} <- start_pipeline(config),
         {:ok, room_io_pid} <- start_room_io(room_pid, pipeline_pid) do
      {:ok,
       %{
         state
         | room_pid: room_pid,
           pipeline_pid: pipeline_pid,
           room_io_pid: room_io_pid,
           room_connected: true
       }}
    else
      {:error, reason} ->
        Logger.error("[AgentSession] Real connect failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_token(config) do
    # T-12-04: Never log the token value — only log room_name
    token =
      AccessToken.new(config.api_key, config.api_secret)
      |> AccessToken.with_identity(config.participant_identity)
      |> AccessToken.with_grants(%Grants{
        room_join: true,
        room: config.room_name
      })
      |> AccessToken.to_jwt()

    {:ok, token}
  rescue
    error ->
      {:error, {:token_build_failed, error}}
  end

  defp start_room(config, token) do
    Room.connect(%Room.Config{
      url: config.server_url,
      token: token,
      auto_subscribe: config.auto_subscribe,
      nif_module: config.nif_module
    })
  end

  defp start_pipeline(%Config{pipeline_config: nil}) do
    {:error, :missing_pipeline_config}
  end

  defp start_pipeline(%Config{pipeline_config: pipeline_config}) do
    Pipeline.start_link(%{pipeline_config | subscriber: self()})
  end

  defp start_room_io(room_pid, pipeline_pid) do
    RoomIO.start_link(%RoomIO.Config{
      room_pid: room_pid,
      pipeline_pid: pipeline_pid
    })
  end

  defp connect_mock(%State{config: config} = state) do
    Logger.info("[AgentSession] Mock mode — simulating room connection for #{config.room_name}")
    session_pid = self()
    spawn_link(fn -> simulate_room_events(session_pid) end)
    {:ok, %{state | room_connected: true}}
  end

  defp simulate_room_events(session_pid) do
    Process.sleep(2_000)

    participant_info = %{
      identity: "user_#{:rand.uniform(1_000)}",
      name: "Test User",
      joined_at: DateTime.utc_now(),
      metadata: %{}
    }

    GenServer.cast(session_pid, {:participant_joined, participant_info})

    Process.sleep(3_000)

    audio_data = :crypto.strong_rand_bytes(4_800)

    _ =
      AudioFrame.new(audio_data,
        sample_rate: 48_000,
        timestamp_us: System.monotonic_time(:microsecond)
      )

    Process.sleep(10_000)
    simulate_room_events(session_pid)
  end

  defp disconnect_from_room_internal(state) do
    if is_pid(state.room_io_pid) and Process.alive?(state.room_io_pid) do
      RoomIO.stop(state.room_io_pid)
    end

    if is_pid(state.pipeline_pid) and Process.alive?(state.pipeline_pid) do
      Pipeline.stop(state.pipeline_pid)
    end

    if is_pid(state.room_pid) and Process.alive?(state.room_pid) do
      Room.disconnect(state.room_pid)
    end

    %{
      state
      | room_pid: nil,
        pipeline_pid: nil,
        room_io_pid: nil,
        room_connected: false,
        participants: %{}
    }
  end
end

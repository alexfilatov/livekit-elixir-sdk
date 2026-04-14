defmodule Livekit.Agents.AgentSession do
  @moduledoc """
  Manages an agent session with a LiveKit room and participants.

  The AgentSession is responsible for:
  - Connecting to LiveKit rooms
  - Managing participant interactions
  - Handling audio/video streams
  - Coordinating between the voice agent and room events
  """

  use GenServer
  require Logger

  alias Livekit.Agents.{VoiceAgent, AudioFrame}
  alias Livekit.{RoomServiceClient}

  defmodule Config do
    @moduledoc """
    Configuration for AgentSession.
    """

    @type t :: %__MODULE__{
      room_name: String.t(),
      participant_identity: String.t(),
      server_url: String.t(),
      api_key: String.t(),
      api_secret: String.t(),
      voice_agent_config: VoiceAgent.Config.t() | nil,
      auto_subscribe: boolean(),
      auto_publish_audio: boolean(),
      auto_publish_video: boolean()
    }

    defstruct [
      :room_name,
      :participant_identity,
      :server_url,
      :api_key,
      :api_secret,
      :voice_agent_config,
      auto_subscribe: true,
      auto_publish_audio: true,
      auto_publish_video: false
    ]
  end

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
      config: Config.t(),
      room_client: RoomServiceClient.t() | nil,
      voice_agent: pid() | nil,
      room_connected: boolean(),
      participants: map(),
      audio_tracks: map(),
      video_tracks: map(),
      session_metadata: map(),
      metrics: map()
    }

    defstruct [
      :config,
      :room_client,
      :voice_agent,
      room_connected: false,
      participants: %{},
      audio_tracks: %{},
      video_tracks: %{},
      session_metadata: %{},
      metrics: %{
        session_start: nil,
        messages_processed: 0,
        audio_frames_processed: 0,
        participants_joined: 0,
        participants_left: 0
      }
    ]
  end

  # Client API

  @doc """
  Starts an AgentSession with the given configuration.
  """
  @spec start_link(Config.t(), GenServer.options()) :: GenServer.on_start()
  def start_link(config, opts \\ []) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  @doc """
  Connects the session to the specified room.
  """
  @spec connect_to_room(pid()) :: :ok | {:error, term()}
  def connect_to_room(session_pid) do
    GenServer.call(session_pid, :connect_to_room, 10_000)
  end

  @doc """
  Disconnects from the current room.
  """
  @spec disconnect_from_room(pid()) :: :ok
  def disconnect_from_room(session_pid) do
    GenServer.call(session_pid, :disconnect_from_room)
  end

  @doc """
  Sends audio data to the room.
  """
  @spec send_audio(pid(), AudioFrame.t()) :: :ok | {:error, term()}
  def send_audio(session_pid, audio_frame) do
    GenServer.cast(session_pid, {:send_audio, audio_frame})
  end

  @doc """
  Sends a text message to the room.
  """
  @spec send_message(pid(), String.t()) :: :ok | {:error, term()}
  def send_message(session_pid, message) do
    GenServer.call(session_pid, {:send_message, message})
  end

  @doc """
  Gets current session status and metrics.
  """
  @spec get_status(pid()) :: map()
  def get_status(session_pid) do
    GenServer.call(session_pid, :get_status)
  end

  @doc """
  Lists all participants in the current room.
  """
  @spec list_participants(pid()) :: list()
  def list_participants(session_pid) do
    GenServer.call(session_pid, :list_participants)
  end

  @doc """
  Updates session metadata.
  """
  @spec update_metadata(pid(), map()) :: :ok
  def update_metadata(session_pid, metadata) do
    GenServer.call(session_pid, {:update_metadata, metadata})
  end

  # GenServer Callbacks

  @impl true
  def init(config) do
    Logger.info("Initializing AgentSession for room: #{config.room_name}")

    # Initialize room service client
    room_client = RoomServiceClient.new(
      config.server_url,
      config.api_key,
      config.api_secret
    )

    # Initialize voice agent if config provided
    voice_agent = case config.voice_agent_config do
      nil ->
        nil

      voice_config ->
        case VoiceAgent.start_link(voice_config) do
          {:ok, pid} ->
            VoiceAgent.connect_to_session(pid, self())
            pid

          {:error, reason} ->
            Logger.error("Failed to start voice agent: #{inspect(reason)}")
            nil
        end
    end

    state = %State{
      config: config,
      room_client: room_client,
      voice_agent: voice_agent,
      metrics: Map.put(%{}, :session_start, DateTime.utc_now())
    }

    # Start with room connection if auto-connect is enabled
    if config.room_name do
      send(self(), :auto_connect)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:connect_to_room, _from, state) do
    case connect_to_room_internal(state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:disconnect_from_room, _from, state) do
    new_state = disconnect_from_room_internal(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:send_message, message}, _from, state) do
    case send_message_to_room(state, message) do
      :ok ->
        new_metrics = Map.update!(state.metrics, :messages_processed, &(&1 + 1))
        {:reply, :ok, %{state | metrics: new_metrics}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      room_connected: state.room_connected,
      room_name: state.config.room_name,
      participant_identity: state.config.participant_identity,
      voice_agent_active: is_pid(state.voice_agent) and Process.alive?(state.voice_agent),
      participants_count: map_size(state.participants),
      audio_tracks_count: map_size(state.audio_tracks),
      metrics: state.metrics,
      session_metadata: state.session_metadata
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:list_participants, _from, state) do
    participants = Map.values(state.participants)
    {:reply, participants, state}
  end

  @impl true
  def handle_call({:update_metadata, metadata}, _from, state) do
    new_metadata = Map.merge(state.session_metadata, metadata)
    new_state = %{state | session_metadata: new_metadata}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:send_audio, audio_frame}, state) do
    new_state = handle_outgoing_audio(state, audio_frame)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:participant_joined, participant_info}, state) do
    Logger.info("Participant joined: #{participant_info.identity}")

    new_participants = Map.put(state.participants, participant_info.identity, participant_info)
    new_metrics = Map.update!(state.metrics, :participants_joined, &(&1 + 1))

    new_state = %{state | participants: new_participants, metrics: new_metrics}

    # Notify voice agent about new participant
    if state.voice_agent do
      send(state.voice_agent, {:participant_joined, participant_info})
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:participant_left, participant_identity}, state) do
    Logger.info("Participant left: #{participant_identity}")

    new_participants = Map.delete(state.participants, participant_identity)
    new_metrics = Map.update!(state.metrics, :participants_left, &(&1 + 1))

    new_state = %{state | participants: new_participants, metrics: new_metrics}

    # Notify voice agent about participant leaving
    if state.voice_agent do
      send(state.voice_agent, {:participant_left, participant_identity})
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:audio_received, participant_identity, audio_data}, state) do
    Logger.debug("Received audio from #{participant_identity}: #{byte_size(audio_data)} bytes")

    # Create audio frame and send to voice agent for processing
    audio_frame = AudioFrame.new(audio_data,
      sample_rate: 48000,
      timestamp_us: System.monotonic_time(:microsecond)
    )

    if state.voice_agent do
      VoiceAgent.process_audio_frame(state.voice_agent, audio_frame)
    end

    new_metrics = Map.update!(state.metrics, :audio_frames_processed, &(&1 + 1))
    new_state = %{state | metrics: new_metrics}

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:auto_connect, state) do
    case connect_to_room_internal(state) do
      {:ok, new_state} ->
        Logger.info("Auto-connected to room: #{state.config.room_name}")
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Auto-connect failed: #{inspect(reason)}")
        # Retry after delay
        Process.send_after(self(), :auto_connect, 5_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    cond do
      pid == state.voice_agent ->
        Logger.warning("Voice agent process went down: #{inspect(reason)}")
        {:noreply, %{state | voice_agent: nil}}

      true ->
        Logger.debug("Monitored process #{inspect(pid)} went down: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("AgentSession received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("AgentSession terminating: #{inspect(reason)}")

    # Clean up voice agent
    if state.voice_agent && Process.alive?(state.voice_agent) do
      GenServer.stop(state.voice_agent, :normal, 5_000)
    end

    # Disconnect from room
    disconnect_from_room_internal(state)

    :ok
  end

  # Private Functions

  defp connect_to_room_internal(state) do
    try do
      # For now, we'll simulate room connection
      # In a real implementation, this would establish WebRTC connection
      Logger.info("Connecting to room: #{state.config.room_name}")

      # Simulate successful connection
      new_state = %{state | room_connected: true}

      # Start room event monitoring (mock)
      start_room_monitoring(new_state)

      {:ok, new_state}
    rescue
      error ->
        Logger.error("Room connection failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp disconnect_from_room_internal(state) do
    Logger.info("Disconnecting from room: #{state.config.room_name}")

    # Clean up room resources
    %{state |
      room_connected: false,
      participants: %{},
      audio_tracks: %{},
      video_tracks: %{}
    }
  end

  defp send_message_to_room(state, message) do
    if state.room_connected do
      Logger.info("Sending message to room: #{message}")
      # In real implementation, this would send via WebRTC data channel
      :ok
    else
      {:error, :not_connected}
    end
  end

  defp handle_outgoing_audio(state, audio_frame) do
    if state.room_connected and state.config.auto_publish_audio do
      Logger.debug("Publishing audio frame: #{byte_size(audio_frame.data)} bytes")
      # In real implementation, this would publish via WebRTC audio track
    end

    new_metrics = Map.update!(state.metrics, :audio_frames_processed, &(&1 + 1))
    %{state | metrics: new_metrics}
  end

  defp start_room_monitoring(state) do
    # Start a process to simulate room events
    # In real implementation, this would listen to WebRTC events
    spawn_link(fn -> simulate_room_events(self()) end)
    state
  end

  defp simulate_room_events(session_pid) do
    # Simulate participant events for development
    Process.sleep(2_000)

    # Simulate participant joining
    participant_info = %{
      identity: "user_#{:rand.uniform(1000)}",
      name: "Test User",
      joined_at: DateTime.utc_now(),
      metadata: %{}
    }

    GenServer.cast(session_pid, {:participant_joined, participant_info})

    # Simulate receiving audio data after a delay
    Process.sleep(3_000)

    # Simulate audio data
    audio_data = :crypto.strong_rand_bytes(4800)  # ~100ms of 48kHz mono PCM16
    GenServer.cast(session_pid, {:audio_received, participant_info.identity, audio_data})

    # Continue simulation
    Process.sleep(10_000)
    simulate_room_events(session_pid)
  end
end
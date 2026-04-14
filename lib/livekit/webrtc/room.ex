defmodule Livekit.WebRTC.Room do
  @moduledoc """
  GenServer managing a LiveKit WebRTC room connection (D-06).

  Wraps the `Livekit.WebRTC.Native` NIFs. Dispatches incoming room events
  (from the Rust event forwarding task) to registered subscriber processes.

  ## Event Messages

  Registered subscribers receive the following messages (D-12):

      {:participant_connected, identity}
      {:participant_disconnected, identity}
      {:track_subscribed, track_sid, identity, track_kind}
      {:track_unsubscribed, track_sid, identity}
      {:track_published, track_sid, identity}
      {:track_unpublished, track_sid, identity}
      {:data_received, payload, topic, identity}
      {:connection_quality_changed, identity, quality}
      {:disconnected, reason}

  Audio frames are delivered directly to the subscriber specified in
  `Livekit.WebRTC.AudioTrack.subscribe/3` — not routed through this GenServer.

  ## NIF module injection

  The NIF module can be overridden via the `:nif_module` config key for testing:

      %Room.Config{url: url, token: token, nif_module: MyMockNIF}

  In production the default `Livekit.WebRTC.Native` is used.

  ## Rust toolchain requirement (D-17)

  Building this application requires Rust and Cargo. Install via:

      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

  The NIF is compiled automatically during `mix compile`.
  """

  use GenServer
  require Logger

  defmodule Config do
    @moduledoc false

    @type t :: %__MODULE__{
            url: String.t(),
            token: String.t(),
            auto_subscribe: boolean(),
            nif_module: module()
          }

    defstruct [:url, :token, auto_subscribe: true, nif_module: Livekit.WebRTC.Native]
  end

  defmodule State do
    @moduledoc false

    defstruct [
      :config,
      :room_ref,
      :nif_module,
      subscribers: [],
      participants: %{},
      metrics: %{
        events_received: 0,
        tracks_subscribed: 0,
        errors: 0
      }
    ]
  end

  # Client API

  @doc """
  Connect to a LiveKit room. Returns `{:ok, pid}` or `{:error, reason}`.

  Config fields:
  - `url`: LiveKit server WebSocket URL (e.g. `"wss://my-room.livekit.cloud"`)
  - `token`: JWT access token from `Livekit.AccessToken.to_jwt/1`
  - `auto_subscribe`: whether to auto-subscribe to tracks (default `true`)
  - `nif_module`: NIF implementation module (default `Livekit.WebRTC.Native`; override in tests)
  """
  @spec connect(Config.t()) :: {:ok, pid()} | {:error, term()}
  def connect(%Config{} = config) do
    # Use start/3 so callers get {:error, reason} on NIF connect failure
    # without receiving a linked EXIT signal. Callers that need crash propagation
    # should monitor the returned pid or start this GenServer under a supervisor.
    GenServer.start(__MODULE__, config)
  end

  @doc "Disconnect from the room and stop the GenServer."
  @spec disconnect(pid()) :: :ok
  def disconnect(pid) do
    GenServer.call(pid, :disconnect, 10_000)
  end

  @doc """
  Register a process to receive room events.
  The subscriber will receive all D-12 event messages.
  """
  @spec subscribe_events(pid(), pid()) :: :ok
  def subscribe_events(pid, subscriber_pid) do
    GenServer.call(pid, {:subscribe_events, subscriber_pid}, 5_000)
  end

  @doc "Returns the opaque NIF room reference for passing to AudioTrack/VideoTrack NIFs."
  @spec room_ref(pid()) :: reference()
  def room_ref(pid) do
    GenServer.call(pid, :room_ref, 5_000)
  end

  @doc "Returns the NIF module in use (default `Livekit.WebRTC.Native`)."
  @spec nif_module(pid()) :: module()
  def nif_module(pid) do
    GenServer.call(pid, :nif_module, 5_000)
  end

  @doc "Returns current room metrics."
  @spec get_metrics(pid()) :: map()
  def get_metrics(pid) do
    GenServer.call(pid, :get_metrics, 5_000)
  end

  # GenServer callbacks

  @impl true
  def init(%Config{} = config) do
    nif = config.nif_module

    case nif.room_connect(config.url, config.token, self()) do
      {:ok, room_ref} ->
        Logger.info("[Livekit.WebRTC.Room] Connected to #{config.url}")
        {:ok, %State{config: config, room_ref: room_ref, nif_module: nif}}

      {:error, reason} ->
        Logger.error("[Livekit.WebRTC.Room] Connect failed: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    state.nif_module.room_disconnect(state.room_ref)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_call({:subscribe_events, subscriber_pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: [subscriber_pid | state.subscribers]}}
  end

  @impl true
  def handle_call(:room_ref, _from, state) do
    {:reply, state.room_ref, state}
  end

  @impl true
  def handle_call(:nif_module, _from, state) do
    {:reply, state.nif_module, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  # Room event handlers — forward to all subscribers (D-10)

  @impl true
  def handle_info({:participant_connected, identity} = event, state) do
    Logger.debug("[Livekit.WebRTC.Room] Participant connected: #{identity}")
    broadcast(state.subscribers, event)
    participants = Map.put(state.participants, identity, %{identity: identity})
    metrics = update_metrics(state.metrics)
    {:noreply, %{state | participants: participants, metrics: metrics}}
  end

  @impl true
  def handle_info({:participant_disconnected, identity} = event, state) do
    Logger.debug("[Livekit.WebRTC.Room] Participant disconnected: #{identity}")
    broadcast(state.subscribers, event)
    participants = Map.delete(state.participants, identity)
    metrics = update_metrics(state.metrics)
    {:noreply, %{state | participants: participants, metrics: metrics}}
  end

  @impl true
  def handle_info({:track_subscribed, _track_sid, _identity, _kind} = event, state) do
    broadcast(state.subscribers, event)

    metrics =
      state.metrics
      |> update_metrics()
      |> Map.update!(:tracks_subscribed, &(&1 + 1))

    {:noreply, %{state | metrics: metrics}}
  end

  @impl true
  def handle_info({:track_unsubscribed, _track_sid, _identity} = event, state) do
    broadcast(state.subscribers, event)
    {:noreply, %{state | metrics: update_metrics(state.metrics)}}
  end

  @impl true
  def handle_info({:track_published, _track_sid, _identity} = event, state) do
    broadcast(state.subscribers, event)
    {:noreply, %{state | metrics: update_metrics(state.metrics)}}
  end

  @impl true
  def handle_info({:track_unpublished, _track_sid, _identity} = event, state) do
    broadcast(state.subscribers, event)
    {:noreply, %{state | metrics: update_metrics(state.metrics)}}
  end

  @impl true
  def handle_info({:data_received, _payload, _topic, _identity} = event, state) do
    broadcast(state.subscribers, event)
    {:noreply, %{state | metrics: update_metrics(state.metrics)}}
  end

  @impl true
  def handle_info({:connection_quality_changed, _identity, _quality} = event, state) do
    broadcast(state.subscribers, event)
    {:noreply, %{state | metrics: update_metrics(state.metrics)}}
  end

  @impl true
  def handle_info({:disconnected, reason}, state) do
    Logger.warning("[Livekit.WebRTC.Room] Disconnected: #{inspect(reason)}")
    broadcast(state.subscribers, {:disconnected, reason})
    {:stop, :normal, state}
  end

  # Catch-all to prevent mailbox overflow (T-11-16 mitigation)
  @impl true
  def handle_info(msg, state) do
    Logger.debug("[Livekit.WebRTC.Room] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Helpers

  defp broadcast(subscribers, event) do
    Enum.each(subscribers, fn pid ->
      send(pid, event)
    end)
  end

  defp update_metrics(metrics) do
    Map.update!(metrics, :events_received, &(&1 + 1))
  end
end

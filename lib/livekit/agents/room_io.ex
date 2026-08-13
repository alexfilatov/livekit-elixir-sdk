defmodule Livekit.Agents.RoomIO do
  @moduledoc """
  GenServer that bridges a LiveKit WebRTC Room to the voice Pipeline.

  `RoomIO` owns the audio routing lifecycle:

  1. On start it subscribes to room events via `Livekit.WebRTC.Room.subscribe_events/2`.
  2. When a remote participant publishes an audio track (`{:track_subscribed, sid, identity, :audio}`),
     RoomIO calls `AudioTrack.subscribe/3` to receive raw PCM frames for that track (if no track is
     currently active). Only the first audio track is tracked at a time.
  3. Incoming `{:audio_frame, track_sid, binary}` messages are wrapped into
     `%AudioFrame{format: :pcm_16, sample_rate: 48_000, channels: 1}` structs and pushed to the
     Pipeline via `Pipeline.push_frame/2` (non-blocking cast).
  4. When the Pipeline finishes a turn it sends `{:pipeline_audio, %AudioFrame{}}` to the process
     registered as `subscriber` in `Pipeline.Config`. RoomIO receives this and publishes the
     synthesised audio back to the room via `AudioTrack.publish/2`.
  5. When a participant disconnects or a track is unsubscribed, RoomIO drops its track reference
     so the next audio track from a new participant can be picked up.

  ## Usage

      {:ok, room_pid} = Livekit.WebRTC.Room.connect(%Room.Config{...})
      {:ok, pipeline_pid} = Livekit.Agents.Pipeline.start_link(%Pipeline.Config{...})

      {:ok, room_io_pid} = Livekit.Agents.RoomIO.start_link(%RoomIO.Config{
        room_pid: room_pid,
        pipeline_pid: pipeline_pid
      })

  ## Metrics

  Call `RoomIO.get_metrics/1` to retrieve a map with `:frames_received`, `:frames_published`,
  and `:errors` counts.
  """

  use GenServer
  require Logger

  alias Livekit.Agents.{AudioFrame, Pipeline}
  alias Livekit.WebRTC.{AudioTrack, Room}

  # ---------------------------------------------------------------------------
  # Config struct
  # ---------------------------------------------------------------------------

  defmodule Config do
    @moduledoc """
    Configuration for `Livekit.Agents.RoomIO`.

    ## Fields

    - `:room_pid` — PID of the connected `Livekit.WebRTC.Room` GenServer (required).
    - `:pipeline_pid` — PID of the `Livekit.Agents.Pipeline` GenServer (required).
    """

    @type t :: %__MODULE__{
            room_pid: pid(),
            pipeline_pid: pid()
          }

    defstruct [:room_pid, :pipeline_pid]
  end

  # ---------------------------------------------------------------------------
  # State struct
  # ---------------------------------------------------------------------------

  defmodule State do
    @moduledoc false

    @type track_entry :: {String.t(), reference()} | nil

    @type t :: %__MODULE__{
            config: Config.t(),
            subscribed_track: track_entry(),
            metrics: %{
              frames_received: non_neg_integer(),
              frames_published: non_neg_integer(),
              errors: non_neg_integer()
            }
          }

    defstruct [
      :config,
      subscribed_track: nil,
      # Publishing paces in real time — a sentence takes as long to publish as
      # it takes to say. Doing that inside the GenServer stopped this process
      # reading its mailbox, so the visitor's microphone piled up and arrived
      # in one burst the moment the agent stopped talking, collapsing the turn
      # detector's timing into a single 10ms "turn". One publish at a time,
      # off the loop, in order.
      publish_task: nil,
      publish_queue: [],
      metrics: %{frames_received: 0, frames_published: 0, errors: 0}
    ]
  end

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @doc """
  Starts a `RoomIO` GenServer.

  Uses `GenServer.start/3` (not `start_link`) so callers receive `{:error, reason}`
  on validation failure instead of an EXIT signal — matching the `Room.connect/1` pattern.
  Callers that need crash propagation should monitor the returned pid or start this
  GenServer under a supervisor.

  Requires a `%RoomIO.Config{}` with both `:room_pid` and `:pipeline_pid` set.
  Returns `{:ok, pid}` on success, or `{:error, :missing_config}` if either pid is `nil`.
  """
  @spec start_link(Config.t()) :: GenServer.on_start()
  def start_link(%Config{} = config), do: GenServer.start(__MODULE__, config)

  @doc """
  Stops the `RoomIO` GenServer cleanly.
  """
  @spec stop(pid()) :: :ok
  def stop(pid), do: GenServer.stop(pid, :normal, 5_000)

  @doc """
  Returns the current RoomIO metrics map.

  ## Keys

  - `:frames_received` — number of audio frames received from the room and forwarded to Pipeline.
  - `:frames_published` — number of audio frames received from Pipeline and published to the room.
  - `:errors` — number of errors encountered (failed subscribe or publish calls).
  """
  @spec get_metrics(pid()) :: %{
          frames_received: non_neg_integer(),
          frames_published: non_neg_integer(),
          errors: non_neg_integer()
        }
  def get_metrics(pid), do: GenServer.call(pid, :get_metrics, 5_000)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%Config{room_pid: nil}), do: {:stop, :missing_config}
  def init(%Config{pipeline_pid: nil}), do: {:stop, :missing_config}

  @impl true
  def init(%Config{} = config) do
    Room.subscribe_events(config.room_pid, self())

    # Claim the pipeline's audio output. `AgentSession` starts the pipeline
    # before RoomIO exists, so it can only name itself as subscriber — and it
    # has no handler for `{:pipeline_audio, _}`, so every synthesised frame
    # was silently discarded. The agent joined the room, said nothing, and
    # published no track: from outside, indistinguishable from an agent that
    # never arrived.
    Livekit.Agents.Pipeline.set_subscriber(config.pipeline_pid, self())

    {:ok, %State{config: config}}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  # Audio track subscribed — subscribe if no track active yet
  @impl true
  def handle_info({:track_subscribed, track_sid, _identity, :audio}, state)
      when is_nil(state.subscribed_track) do
    case AudioTrack.subscribe(state.config.room_pid, track_sid, self()) do
      {:ok, track_ref} ->
        Logger.info("[RoomIO] Subscribed to audio track #{track_sid}")

        # Somebody is publishing a microphone, so somebody is in the room to
        # hear the opening line. Greeting any earlier plays it to nobody: the
        # agent is dispatched when the room is created, seconds before the
        # visitor's browser finishes connecting, and WebRTC buffers nothing.
        Pipeline.greet(state.config.pipeline_pid)

        {:noreply, %{state | subscribed_track: {track_sid, track_ref}}}

      {:error, reason} ->
        Logger.warning("[RoomIO] Failed to subscribe to track #{track_sid}: #{inspect(reason)}")
        metrics = Map.update!(state.metrics, :errors, &(&1 + 1))
        {:noreply, %{state | metrics: metrics}}
    end
  end

  # Audio track subscribed — already have one active, ignore
  @impl true
  def handle_info({:track_subscribed, _track_sid, _identity, :audio}, state) do
    {:noreply, state}
  end

  # Non-audio track subscribed — ignore. Logged because an unrecognised kind
  # silently ends the conversation here: no subscribe, no greeting, no audio.
  @impl true
  def handle_info({:track_subscribed, _track_sid, _identity, kind}, state) do
    Logger.info("[RoomIO] Ignoring #{inspect(kind)} track")
    {:noreply, state}
  end

  # Incoming audio from room — wrap and push to pipeline
  @impl true
  def handle_info({:audio_frame, _track_sid, binary}, state) do
    frame =
      AudioFrame.new(binary,
        format: :pcm_16,
        sample_rate: 48_000,
        channels: 1
      )

    Pipeline.push_frame(state.config.pipeline_pid, frame)

    # Once at the start and then rarely: enough to tell "the visitor's audio is
    # arriving" from "it never came", without a line per 10ms of speech.
    if rem(state.metrics.frames_received, 500) == 0 do
      Logger.info("[RoomIO] Received #{state.metrics.frames_received + 1} audio frames")
    end

    metrics = Map.update!(state.metrics, :frames_received, &(&1 + 1))
    {:noreply, %{state | metrics: metrics}}
  end

  # Synthesised audio from pipeline — publish back to room, off the loop.
  @impl true
  def handle_info({:pipeline_audio, %AudioFrame{} = frame}, state) do
    {:noreply, enqueue_publish(state, frame)}
  end

  # A publish finished.
  @impl true
  def handle_info({ref, result}, %State{publish_task: %Task{ref: task_ref}} = state)
      when ref == task_ref do
    Process.demonitor(ref, [:flush])

    state =
      case result do
        :ok ->
          if state.metrics.frames_published == 0 do
            Logger.info("[RoomIO] Published first audio frame")
          end

          %{state | metrics: Map.update!(state.metrics, :frames_published, &(&1 + 1))}

        {:error, reason} ->
          Logger.warning("[RoomIO] Failed to publish pipeline audio: #{inspect(reason)}")

          metrics =
            state.metrics
            |> Map.update!(:frames_published, &(&1 + 1))
            |> Map.update!(:errors, &(&1 + 1))

          %{state | metrics: metrics}
      end

    {:noreply, start_next_publish(%{state | publish_task: nil})}
  end

  # The publishing task exited; its result was handled above.
  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}

  # Participant disconnected — drop track reference
  @impl true
  def handle_info({:participant_disconnected, _identity}, state) do
    unsubscribe_track(state.subscribed_track)
    {:noreply, %{state | subscribed_track: nil}}
  end

  # Track unsubscribed — drop track reference
  @impl true
  def handle_info({:track_unsubscribed, _track_sid, _identity}, state) do
    unsubscribe_track(state.subscribed_track)
    {:noreply, %{state | subscribed_track: nil}}
  end

  # Catch-all — log and discard
  @impl true
  def handle_info(msg, state) do
    Logger.debug("[RoomIO] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  # One utterance publishes at a time: two concurrent publishes would interleave
  # their 10ms frames into the same track and come out as noise.
  defp enqueue_publish(%State{publish_task: nil} = state, frame),
    do: %{state | publish_task: publish_async(state, frame)}

  defp enqueue_publish(%State{} = state, frame),
    do: %{state | publish_queue: state.publish_queue ++ [frame]}

  defp start_next_publish(%State{publish_queue: []} = state), do: state

  defp start_next_publish(%State{publish_queue: [frame | rest]} = state),
    do: %{state | publish_task: publish_async(state, frame), publish_queue: rest}

  defp publish_async(%State{} = state, frame) do
    room_pid = state.config.room_pid
    Task.async(fn -> AudioTrack.publish(room_pid, frame) end)
  end

  defp unsubscribe_track(nil), do: :ok

  defp unsubscribe_track({_track_sid, track_ref}) do
    AudioTrack.unsubscribe(track_ref)
  end
end

defmodule Livekit.Agents.Pipeline.TurnDetector do
  @moduledoc """
  Timer-based speech turn boundary detector.

  `TurnDetector` is a GenServer that consumes `{classification, frame}` tuples
  (where `classification` is `:speech` or `:silence` as returned by
  `Livekit.Agents.Pipeline.EnergyVAD.classify/2`) and emits high-level turn
  events to a subscriber process:

  - `{:turn_start, timestamp_us}` — sent when the first speech frame arrives
    after a period of silence.
  - `{:turn_end, [AudioFrame.t()]}` — sent when silence has persisted for at
    least `silence_ms` milliseconds after the last speech frame; carries all
    accumulated frames from the utterance.

  The silence timer is reset whenever a speech frame arrives during the silence
  window, preventing premature `{:turn_end, _}` messages when the speaker
  pauses briefly mid-sentence.

  ## Usage

      {:ok, pid} = TurnDetector.start_link(subscriber: self(), silence_ms: 500)

      # Push frames from your audio source:
      TurnDetector.push_frame(pid, {:speech, audio_frame})
      TurnDetector.push_frame(pid, {:silence, audio_frame})

      # Receive events in your process:
      receive do
        {:turn_start, ts}    -> IO.puts("Speech started at \#{ts} µs")
        {:turn_end, frames}  -> IO.puts("Turn ended; \#{length(frames)} frames captured")
      end
  """

  use GenServer

  require Logger

  alias Livekit.Agents.AudioFrame

  # ---------------------------------------------------------------------------
  # Config struct
  # ---------------------------------------------------------------------------

  defmodule Config do
    @moduledoc """
    Configuration for `Livekit.Agents.Pipeline.TurnDetector`.

    ## Fields

    - `:silence_ms` — milliseconds of consecutive silence after which
      `{:turn_end, frames}` is sent. Defaults to `500`.
    - `:subscriber` — PID of the process that receives turn events (required).
    """

    @type t :: %__MODULE__{silence_ms: pos_integer(), subscriber: pid()}
    defstruct silence_ms: 500, subscriber: nil
  end

  # ---------------------------------------------------------------------------
  # State struct
  # ---------------------------------------------------------------------------

  defmodule State do
    @moduledoc false

    @type vad_state :: :silence | :speaking

    @type t :: %__MODULE__{
            config: Config.t(),
            vad_state: vad_state(),
            silence_timer: reference() | nil,
            utterance_frames: [AudioFrame.t()]
          }

    defstruct config: nil, vad_state: :silence, silence_timer: nil, utterance_frames: []
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts a `TurnDetector` GenServer linked to the calling process.

  ## Options

  - `:subscriber` — (required) PID that will receive turn events.
  - `:silence_ms` — silence window in milliseconds before `{:turn_end, _}` fires.
    Defaults to `500`.

  Returns `{:ok, pid}` on success, or `{:error, reason}` if `:subscriber` is not
  a PID.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    subscriber = Keyword.get(opts, :subscriber)
    silence_ms = Keyword.get(opts, :silence_ms, 500)

    config = %Config{silence_ms: silence_ms, subscriber: subscriber}

    case validate_config(config) do
      :ok -> GenServer.start_link(__MODULE__, config)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Pushes a classified audio frame to the detector (non-blocking cast).

  `classification` must be `:speech` or `:silence` (as returned by
  `EnergyVAD.classify/2`). `frame` is the corresponding `AudioFrame.t()`.
  """
  @spec push_frame(pid(), {:speech | :silence, AudioFrame.t()}) :: :ok
  def push_frame(pid, {classification, %AudioFrame{} = frame})
      when classification in [:speech, :silence] do
    GenServer.cast(pid, {:push_frame, classification, frame})
  end

  @doc """
  Resets the detector: cancels any pending silence timer, clears accumulated
  frames, and returns to `:silence` VAD state.
  """
  @spec reset(pid()) :: :ok
  def reset(pid) do
    GenServer.cast(pid, :reset)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%Config{} = config) do
    {:ok, %State{config: config}}
  end

  @impl true
  def handle_cast({:push_frame, :speech, frame}, %State{} = state) do
    # 1. Cancel any pending silence timer
    state = cancel_silence_timer(state)

    # 2. If transitioning from silence -> speaking, notify subscriber
    state =
      if state.vad_state == :silence do
        send(state.config.subscriber, {:turn_start, frame.timestamp_us})
        %{state | vad_state: :speaking}
      else
        state
      end

    # 3. Accumulate the speech frame (append in order)
    new_frames = state.utterance_frames ++ [frame]
    {:noreply, %{state | utterance_frames: new_frames, silence_timer: nil}}
  end

  @impl true
  def handle_cast({:push_frame, :silence, _frame}, %State{} = state) do
    # Only start/reset the timer when currently speaking
    state =
      if state.vad_state == :speaking do
        state = cancel_silence_timer(state)
        timer = Process.send_after(self(), :silence_timeout, state.config.silence_ms)
        %{state | silence_timer: timer}
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_cast(:reset, %State{} = state) do
    state = cancel_silence_timer(state)

    {:noreply, %{state | utterance_frames: [], silence_timer: nil, vad_state: :silence}}
  end

  @impl true
  def handle_info(:silence_timeout, %State{} = state) do
    send(state.config.subscriber, {:turn_end, state.utterance_frames})

    {:noreply, %{state | utterance_frames: [], silence_timer: nil, vad_state: :silence}}
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  @spec validate_config(Config.t()) :: :ok | {:error, term()}
  defp validate_config(%Config{subscriber: subscriber}) when is_pid(subscriber), do: :ok
  defp validate_config(%Config{}), do: {:error, :subscriber_must_be_pid}

  @spec cancel_silence_timer(State.t()) :: State.t()
  defp cancel_silence_timer(%State{silence_timer: nil} = state), do: state

  defp cancel_silence_timer(%State{silence_timer: timer} = state) do
    Process.cancel_timer(timer)
    %{state | silence_timer: nil}
  end
end

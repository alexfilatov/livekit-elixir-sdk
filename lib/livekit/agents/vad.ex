defmodule Livekit.Agents.VAD do
  @moduledoc """
  Behaviour contract for Voice Activity Detection providers.

  Any module that `use Livekit.Agents.VAD` becomes a conforming VAD provider
  and can be plugged into the voice pipeline via the `{module, config}` tuple.

  VAD is streaming-only by design — there is no batch API. Providers implement
  `stream/1` to start a VAD process that accepts audio frames and emits speech
  activity events.

  ## Usage

      {:ok, vad_pid} = MyVAD.stream(%{threshold: 0.5})
      # Send audio frames to the VAD process:
      send(vad_pid, {:audio_frame, %Livekit.Agents.AudioFrame{}})
      # vad_pid sends {:vad_event, %Livekit.Agents.VAD.VADEvent{}} to self()

  ## Implementing a provider

      defmodule MyVAD do
        use Livekit.Agents.VAD

        @impl true
        def stream(_config) do
          subscriber = self()
          pid = spawn_link(fn -> vad_loop(subscriber) end)
          {:ok, pid}
        end

        @impl true
        def capabilities do
          %{realtime: true, speech_probability: true}
        end

        defp vad_loop(subscriber) do
          receive do
            {:audio_frame, frame} ->
              # detect speech in frame
              event = %Livekit.Agents.VAD.VADEvent{type: :inference, probability: 0.9, frames: [frame]}
              send(subscriber, {:vad_event, event})
              vad_loop(subscriber)
          end
        end
      end

  VAD providers handling API keys or resources must override `validate_config/1`
  to verify required fields are present.
  """

  @type config :: map()
  @type error_reason :: :api_error | :timeout | :invalid_config | :rate_limited | term()

  @doc """
  Starts a VAD streaming process.

  Returns `{:ok, vad_pid}` where `vad_pid` is the PID of a process that:

  - Accepts `{:audio_frame, %Livekit.Agents.AudioFrame{}}` messages via `send/2`.
  - Sends `{:vad_event, %Livekit.Agents.VAD.VADEvent{}}` messages to the process
    that called `stream/1` (captured as `self()` at invocation time).
  - Sends `{:error, reason}` to the subscriber on failure and exits.

  `config` is a map of provider-specific configuration (e.g. detection threshold).
  """
  @callback stream(config :: config()) :: {:ok, pid()} | {:error, error_reason()}

  @doc """
  Returns a map describing the provider's capabilities.

  Required keys:

  - `:realtime` — whether the provider operates in real time (always `true` for VAD)
  - `:speech_probability` — whether the provider emits per-frame speech probability scores
  """
  @callback capabilities() :: %{
              realtime: boolean(),
              speech_probability: boolean()
            }

  @doc """
  Validates a provider configuration map.

  Returns `:ok` if the config is valid, or `{:error, reason}` otherwise.
  The default implementation (injected by `use Livekit.Agents.VAD`) returns `:ok`.
  Override this in your provider for real validation.
  """
  @callback validate_config(config :: config()) :: :ok | {:error, error_reason()}

  # stream/1 is NOT optional — VAD has no batch mode (D-04)
  @optional_callbacks [validate_config: 1]

  @doc """
  Injects `@behaviour Livekit.Agents.VAD` and a default `validate_config/1`
  that returns `:ok`. Override `validate_config/1` in your provider module to
  add real validation.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Livekit.Agents.VAD

      @impl Livekit.Agents.VAD
      def validate_config(_config), do: :ok

      defoverridable validate_config: 1
    end
  end
end

defmodule Livekit.Agents.VAD.VADEvent do
  @moduledoc """
  Event emitted by a VAD streaming process.

  Streaming processes send `{:vad_event, %VADEvent{}}` to the subscriber
  process (the PID that called `stream/1`).

  ## Event types

  - `:speech_start` — speech has been detected; `frames` contains the triggering audio frames
  - `:speech_end` — silence detected after speech; the utterance is complete. `frames` contains
    all audio frames for the complete utterance (useful for downstream transcription)
  - `:inference` — an intermediate probability reading during ongoing speech; `frames` contains
    the current batch of audio frames evaluated

  ## Fields

  - `:type` — one of `:speech_start`, `:speech_end`, or `:inference` (required, no default)
  - `:probability` — speech probability score in the range `0.0..1.0`
  - `:frames` — list of `AudioFrame.t()` associated with the event
  """

  alias Livekit.Agents.AudioFrame

  @type event_type :: :speech_start | :speech_end | :inference

  @type t :: %__MODULE__{
          type: event_type(),
          probability: float(),
          frames: [AudioFrame.t()]
        }

  defstruct [:type, probability: 0.0, frames: []]
end

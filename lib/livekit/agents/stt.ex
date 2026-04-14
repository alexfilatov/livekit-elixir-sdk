defmodule Livekit.Agents.STT do
  @moduledoc """
  Behaviour contract for Speech-to-Text providers.

  Any module that `use Livekit.Agents.STT` becomes a conforming STT provider
  and can be plugged into the voice pipeline via the `{module, config}` tuple.

  ## Batch usage

      {:ok, event} = MySTT.transcribe(audio_binary, language: "en")
      # event is a %Livekit.Agents.STT.SpeechEvent{type: :final, text: "hello", ...}

  ## Streaming usage

      {:ok, stream_pid} = MySTT.stream(config)
      # stream_pid sends {:speech_event, %Livekit.Agents.STT.SpeechEvent{}} to self()
      # The terminal event has type: :end

  ## Implementing a provider

      defmodule MySTT do
        use Livekit.Agents.STT

        @impl true
        def transcribe(audio_binary, _opts) do
          # call external API, return final transcript
          {:ok, %Livekit.Agents.STT.SpeechEvent{type: :final, text: "hello", confidence: 0.99, language: "en"}}
        end

        @impl true
        def capabilities do
          %{streaming: false, interim_results: false, diarization: false, languages: ["en"]}
        end
      end

  Optional callbacks (`stream/1`, `validate_config/1`) are not required for batch-only providers.
  Use `function_exported?(module, :stream, 1)` to check streaming support at runtime.
  """

  alias Livekit.Agents.STT.SpeechEvent

  @type config :: map()
  @type error_reason :: :api_error | :timeout | :invalid_config | :rate_limited | term()

  @doc """
  Transcribes an audio binary and returns a final `SpeechEvent`.

  `audio` is a raw audio binary. `opts` may include provider-specific options
  such as `language: "en"` or `model: "nova-2"`.
  """
  @callback transcribe(audio :: binary(), opts :: keyword()) ::
              {:ok, SpeechEvent.t()} | {:error, error_reason()}

  @doc """
  Starts a streaming transcription process.

  Returns `{:ok, stream_pid}` where `stream_pid` is the PID of a process that:

  - Sends `{:speech_event, %Livekit.Agents.STT.SpeechEvent{}}` messages to the
    process that called `stream/1` (captured as `self()` at invocation time).
  - Terminates normally after sending the terminal event (`type: :end`).
  - Sends `{:error, reason}` to the subscriber on failure.

  `config` is a map of provider-specific configuration.
  """
  @callback stream(config :: config()) :: {:ok, pid()} | {:error, error_reason()}

  @doc """
  Returns a map describing the provider's capabilities.

  Required keys:

  - `:streaming` — whether the provider supports `stream/1`
  - `:interim_results` — whether the provider emits `:interim` events mid-utterance
  - `:diarization` — whether the provider supports speaker diarization
  - `:languages` — list of BCP-47 language codes supported (e.g. `["en", "fr"]`)
  """
  @callback capabilities() :: %{
              streaming: boolean(),
              interim_results: boolean(),
              diarization: boolean(),
              languages: [String.t()]
            }

  @doc """
  Validates a provider configuration map.

  Returns `:ok` if the config is valid, or `{:error, reason}` otherwise.
  The default implementation (injected by `use Livekit.Agents.STT`) returns `:ok`.
  Override this in your provider for real validation.
  """
  @callback validate_config(config :: config()) :: :ok | {:error, error_reason()}

  @optional_callbacks [stream: 1, validate_config: 1]

  @doc """
  Injects `@behaviour Livekit.Agents.STT` and a default `validate_config/1`
  that returns `:ok`. Override `validate_config/1` in your provider module to
  add real validation.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Livekit.Agents.STT

      @impl Livekit.Agents.STT
      def validate_config(_config), do: :ok

      defoverridable validate_config: 1
    end
  end
end

defmodule Livekit.Agents.STT.SpeechEvent do
  @moduledoc """
  Event emitted by an STT streaming process.

  Streaming processes send `{:speech_event, %SpeechEvent{}}` to the subscriber
  process (the PID that called `stream/1`). The event stream proceeds through
  `:start` → zero or more `:interim` → `:final` → `:end`.

  A `:end` type event signals that the stream has completed and the streaming
  process will exit normally.

  ## Fields

  - `:type` — one of `:start`, `:interim`, `:final`, or `:end` (required, no default)
  - `:text` — transcript text; empty string for `:start` and `:end` events
  - `:confidence` — confidence score in the range `0.0..1.0`; `0.0` for non-final events
  - `:language` — BCP-47 language code of the detected or configured language
  """

  @type event_type :: :start | :interim | :final | :end

  @type t :: %__MODULE__{
          type: event_type(),
          text: String.t(),
          confidence: float(),
          language: String.t()
        }

  defstruct [
    :type,
    text: "",
    confidence: 0.0,
    language: "en"
  ]
end

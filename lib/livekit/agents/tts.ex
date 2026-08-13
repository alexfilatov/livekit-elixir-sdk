defmodule Livekit.Agents.TTS do
  @moduledoc """
  Behaviour contract for Text-to-Speech providers.

  Any module that `use Livekit.Agents.TTS` becomes a conforming TTS provider
  and can be plugged into the voice pipeline via the `{module, config}` tuple.

  ## Batch usage

      {:ok, audio_binary} = MyTTS.synthesize("Hello, world!", voice: "alloy", format: :pcm)

  ## Streaming usage

      {:ok, stream_pid} = MyTTS.stream(config)
      # Feed text to the stream process:
      send(stream_pid, {:text_chunk, "Hello, "})
      send(stream_pid, {:text_chunk, "world!"})
      # stream_pid sends {:audio_frame, %Livekit.Agents.AudioFrame{}} to self()
      # stream_pid sends :stream_done to self() when finished

  ## Implementing a provider

      defmodule MyTTS do
        use Livekit.Agents.TTS

        @impl true
        def synthesize(text, _opts) do
          # call external API, return raw audio binary
          {:ok, <<0, 1, 2, 3>>}
        end

        @impl true
        def capabilities do
          %{streaming: false, voices: ["default"], audio_formats: [:pcm], word_timing: false}
        end
      end

  Optional callbacks (`stream/1`, `validate_config/1`) are not required for batch-only providers.
  Use `function_exported?(module, :stream, 1)` to check streaming support at runtime.
  """

  @type config :: map()
  @type error_reason :: :api_error | :timeout | :invalid_config | :rate_limited | term()
  @type audio_format :: :pcm | :mp3 | :opus | :aac | :flac

  @doc """
  Synthesizes `text` into audio and returns the raw audio binary.

  `opts` may include provider-specific options such as:

  - `voice: String.t()` — the voice identifier to use
  - `format: audio_format()` — the desired output audio format
  """
  @callback synthesize(text :: String.t(), opts :: keyword()) ::
              {:ok, binary()} | {:error, error_reason()}

  @doc """
  Starts a streaming synthesis process.

  Returns `{:ok, stream_pid}` where `stream_pid` is the PID of a process that:

  - Accepts `{:text_chunk, String.t()}` messages with text fragments to synthesize.
  - Sends `{:audio_frame, AudioFrame.t()}` messages to the subscriber process
    (the PID that called `stream/1`, captured as `self()` at invocation time).
  - Sends `:stream_done` to the subscriber when all audio has been emitted.
  - Sends `{:error, reason}` to the subscriber on failure and exits.

  `config` is a map of provider-specific configuration.
  """
  @callback stream(config :: config()) :: {:ok, pid()} | {:error, error_reason()}

  @doc """
  Returns a map describing the provider's capabilities.

  Required keys:

  - `:streaming` — whether the provider supports `stream/1`
  - `:voices` — list of supported voice identifiers
  - `:audio_formats` — list of supported `audio_format()` values
  - `:word_timing` — whether the provider can emit per-word timing metadata
  """
  @callback capabilities() :: %{
              streaming: boolean(),
              voices: [String.t()],
              audio_formats: [audio_format()],
              word_timing: boolean()
            }

  @doc """
  Validates a provider configuration map.

  Returns `:ok` if the config is valid, or `{:error, reason}` otherwise.
  The default implementation (injected by `use Livekit.Agents.TTS`) returns `:ok`.
  Override this in your provider module to add real validation.
  """
  @callback validate_config(config :: config()) :: :ok | {:error, error_reason()}

  @optional_callbacks [stream: 1, validate_config: 1]

  @doc """
  Injects `@behaviour Livekit.Agents.TTS` and a default `validate_config/1`
  that returns `:ok`. Override `validate_config/1` in your provider module to
  add real validation.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Livekit.Agents.TTS

      @impl Livekit.Agents.TTS
      def validate_config(_config), do: :ok

      defoverridable validate_config: 1
    end
  end
end

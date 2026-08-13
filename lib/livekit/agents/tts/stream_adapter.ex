defmodule Livekit.Agents.TTS.StreamAdapter do
  @moduledoc """
  Stream adapter for batch-only TTS providers.

  Wraps a provider that only implements `synthesize/2` (no `stream/1`) and
  presents a streaming interface. Text chunks sent to the stream process are
  accumulated; when each sentence boundary is detected (or when the stream is
  explicitly flushed), the accumulated text is synthesized in a single batch
  call and the audio binary is wrapped in an `AudioFrame` and forwarded to the
  subscriber.

  This lets batch-only providers be used anywhere a streaming TTS is expected,
  such as in `Livekit.Agents.Pipeline`.

  ## Sentence tokenization

  Text chunks are split on common sentence-ending punctuation (`.`, `!`, `?`,
  followed by whitespace or end-of-string). Each complete sentence triggers a
  synthesis call. Any remaining text is flushed when `:flush` is sent.

  ## Protocol

  The stream process accepts:

  - `{:text_chunk, String.t()}` — text to accumulate
  - `:flush` — synthesize any remaining buffered text and signal `:stream_done`

  The stream process sends to the subscriber:

  - `{:audio_frame, %Livekit.Agents.AudioFrame{}}` — synthesized audio per sentence
  - `:stream_done` — signals all audio has been emitted
  - `{:error, reason}` — on synthesis failure

  ## Usage

      config = %Livekit.Agents.TTS.StreamAdapter.Config{
        provider: {MyBatchTTS, %MyBatchTTS.Config{api_key: "..."}},
        sample_rate: 24_000
      }

      {:ok, stream_pid} = Livekit.Agents.TTS.StreamAdapter.stream(config)

      send(stream_pid, {:text_chunk, "Hello! How are you?"})
      send(stream_pid, :flush)

      receive do
        {:audio_frame, frame} -> IO.inspect(byte_size(frame.data))
        :stream_done -> IO.puts("Done!")
      end
  """

  use Livekit.Agents.TTS

  require Logger

  alias Livekit.Agents.AudioFrame

  # Regex matching sentence-ending punctuation followed by whitespace or EOS
  @sentence_end_re ~r/(?<=[.!?])\s+/

  # ---------------------------------------------------------------------------
  # Config
  # ---------------------------------------------------------------------------

  defmodule Config do
    @moduledoc """
    Configuration for the TTS StreamAdapter.

    ## Fields

    - `:provider` — `{module, config}` tuple for the batch TTS provider (required)
    - `:sample_rate` — audio sample rate for emitted `AudioFrame`s (default: `48_000`)
    - `:sentence_tokenize` — when `true`, synthesize at sentence boundaries for
      lower latency (default: `true`)
    """

    @type t :: %__MODULE__{
            provider: {module(), map()},
            sample_rate: pos_integer(),
            sentence_tokenize: boolean()
          }

    defstruct provider: nil,
              sample_rate: 48_000,
              sentence_tokenize: true
  end

  # ---------------------------------------------------------------------------
  # Behaviour callbacks
  # ---------------------------------------------------------------------------

  @doc "Returns capabilities of the stream adapter."
  @impl Livekit.Agents.TTS
  @spec capabilities() :: %{
          streaming: boolean(),
          voices: [String.t()],
          audio_formats: [Livekit.Agents.TTS.audio_format()],
          word_timing: boolean()
        }
  def capabilities do
    %{streaming: true, voices: ["default"], audio_formats: [:pcm], word_timing: false}
  end

  @doc """
  Validates the stream adapter config. `:provider` must be set.
  """
  @impl Livekit.Agents.TTS
  @spec validate_config(Config.t()) :: :ok | {:error, term()}
  def validate_config(%Config{provider: nil}), do: {:error, :missing_provider}
  def validate_config(%Config{provider: {_mod, _cfg}}), do: :ok

  @doc """
  `synthesize/2` is not the primary interface — use `stream/1` instead.

  Delegates directly to the underlying batch provider if a `:config` option
  with a `%Config{}` is supplied.
  """
  @impl Livekit.Agents.TTS
  @spec synthesize(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def synthesize(text, opts \\ []) do
    config = Keyword.fetch!(opts, :config)
    {provider_mod, provider_cfg} = config.provider
    provider_opts = Keyword.put(Keyword.delete(opts, :config), :config, provider_cfg)
    provider_mod.synthesize(text, provider_opts)
  end

  @doc """
  Starts a streaming synthesis session backed by the batch provider.

  Returns `{:ok, stream_pid}`. The returned process accepts `{:text_chunk, text}`
  and `:flush` messages and sends `{:audio_frame, frame}` + `:stream_done` to
  the caller.

  `config` must be a `%StreamAdapter.Config{}`.
  """
  @impl Livekit.Agents.TTS
  @spec stream(Config.t()) :: {:ok, pid()} | {:error, term()}
  def stream(%Config{} = config) do
    subscriber = self()
    pid = spawn(fn -> stream_loop(config, subscriber, "") end)
    {:ok, pid}
  end

  # ---------------------------------------------------------------------------
  # Private — stream process loop
  # ---------------------------------------------------------------------------

  defp stream_loop(config, subscriber, buffer) do
    receive do
      {:text_chunk, text} when is_binary(text) ->
        new_buffer = buffer <> text

        if config.sentence_tokenize do
          {sentences, remaining} = split_sentences(new_buffer)

          Enum.each(sentences, fn sentence ->
            synthesize_and_emit(config, subscriber, sentence)
          end)

          stream_loop(config, subscriber, remaining)
        else
          stream_loop(config, subscriber, new_buffer)
        end

      :flush ->
        if buffer != "" do
          synthesize_and_emit(config, subscriber, buffer)
        end

        send(subscriber, :stream_done)

      other ->
        Logger.warning("[TTS.StreamAdapter] Unexpected message: #{inspect(other)}")
        stream_loop(config, subscriber, buffer)
    end
  end

  # Splits buffer into complete sentences and a trailing incomplete fragment.
  # Returns {[complete_sentences], remaining_fragment}.
  @spec split_sentences(String.t()) :: {[String.t()], String.t()}
  defp split_sentences(text) do
    parts = Regex.split(@sentence_end_re, text, include_captures: false, trim: false)

    case parts do
      [single] ->
        {[], single}

      multiple ->
        {complete, [last]} = Enum.split(multiple, length(multiple) - 1)
        sentences = Enum.reject(complete, &(&1 == ""))
        {sentences, last}
    end
  end

  defp synthesize_and_emit(config, subscriber, text) do
    text = String.trim(text)

    if text == "" do
      :ok
    else
      {provider_mod, provider_cfg} = config.provider
      provider_opts = [config: provider_cfg]

      case provider_mod.synthesize(text, provider_opts) do
        {:ok, audio_binary} ->
          frame =
            AudioFrame.new(audio_binary,
              sample_rate: config.sample_rate,
              channels: 1,
              format: :pcm_16
            )

          send(subscriber, {:audio_frame, frame})

        {:error, reason} ->
          Logger.error(
            "[TTS.StreamAdapter] Synthesis failed for text #{inspect(text)}: #{inspect(reason)}"
          )

          send(subscriber, {:error, reason})
      end
    end
  end
end

defmodule Livekit.Agents.STT.StreamAdapter do
  @moduledoc """
  Stream adapter for batch-only STT providers.

  Wraps a provider that only implements `transcribe/2` (no `stream/1`) and
  presents a streaming interface. Audio frames are accumulated in a buffer;
  when the stream is closed via `finish/1`, the buffered audio is sent to the
  underlying provider as a single batch request and the transcript is delivered
  as a sequence of `SpeechEvent` messages.

  This lets batch-only providers be used anywhere a streaming STT is expected,
  such as in `Livekit.Agents.Pipeline`.

  ## Event sequence emitted to subscriber

      {:speech_event, %SpeechEvent{type: :start}}
      {:speech_event, %SpeechEvent{type: :final, text: "...", confidence: ...}}
      {:speech_event, %SpeechEvent{type: :end}}

  ## Usage

      config = %Livekit.Agents.STT.StreamAdapter.Config{
        provider: {MyBatchSTT, %MyBatchSTT.Config{api_key: "..."}},
        language: "en"
      }

      {:ok, stream_pid} = Livekit.Agents.STT.StreamAdapter.stream(config)

      # Send audio frames
      send(stream_pid, {:audio_frame, audio_binary})

      # Signal end of audio
      Livekit.Agents.STT.StreamAdapter.finish(stream_pid)

      # Receive events
      receive do
        {:speech_event, event} -> IO.inspect(event)
      end
  """

  use Livekit.Agents.STT

  require Logger

  alias Livekit.Agents.STT.SpeechEvent

  # ---------------------------------------------------------------------------
  # Config
  # ---------------------------------------------------------------------------

  defmodule Config do
    @moduledoc """
    Configuration for the STT StreamAdapter.

    ## Fields

    - `:provider` — `{module, config}` tuple for the batch STT provider (required)
    - `:language` — BCP-47 language code forwarded to the provider (default: `"en"`)
    - `:sample_rate` — audio sample rate in Hz (default: `48_000`)
    """

    @type t :: %__MODULE__{
            provider: {module(), map()},
            language: String.t(),
            sample_rate: pos_integer()
          }

    defstruct provider: nil,
              language: "en",
              sample_rate: 48_000
  end

  # ---------------------------------------------------------------------------
  # Behaviour callbacks
  # ---------------------------------------------------------------------------

  @doc "Returns capabilities of the stream adapter."
  @impl Livekit.Agents.STT
  @spec capabilities() :: %{
          streaming: boolean(),
          interim_results: boolean(),
          diarization: boolean(),
          languages: [String.t()]
        }
  def capabilities do
    %{streaming: true, interim_results: false, diarization: false, languages: ["en"]}
  end

  @doc """
  Validates the stream adapter config. `:provider` must be set.
  """
  @impl Livekit.Agents.STT
  @spec validate_config(Config.t()) :: :ok | {:error, term()}
  def validate_config(%Config{provider: nil}), do: {:error, :missing_provider}
  def validate_config(%Config{provider: {_mod, _cfg}}), do: :ok

  @doc """
  `transcribe/2` is not the primary interface — use `stream/1` instead.

  Delegates directly to the underlying batch provider if a `:config` option
  with a `%Config{}` is supplied.
  """
  @impl Livekit.Agents.STT
  @spec transcribe(binary(), keyword()) :: {:ok, SpeechEvent.t()} | {:error, term()}
  def transcribe(audio, opts \\ []) do
    config = Keyword.fetch!(opts, :config)
    {provider_mod, provider_cfg} = config.provider
    provider_opts = [config: provider_cfg]
    provider_mod.transcribe(audio, provider_opts)
  end

  @doc """
  Starts a streaming session backed by the batch provider.

  Returns `{:ok, stream_pid}` where `stream_pid` accepts:

  - `{:audio_frame, binary()}` — appends audio data to the buffer
  - `:finish` — triggers batch transcription and emits SpeechEvents to the
    subscriber, then exits

  `config` must be a `%StreamAdapter.Config{}`.
  """
  @impl Livekit.Agents.STT
  @spec stream(Config.t()) :: {:ok, pid()} | {:error, term()}
  def stream(%Config{} = config) do
    subscriber = self()
    pid = spawn(fn -> stream_loop(config, subscriber, []) end)
    {:ok, pid}
  end

  @doc """
  Signals the stream process to flush buffered audio and emit final events.

  Call this when you have finished sending audio to the stream.
  """
  @spec finish(pid()) :: :ok
  def finish(stream_pid) do
    send(stream_pid, :finish)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Private — stream process loop
  # ---------------------------------------------------------------------------

  defp stream_loop(config, subscriber, audio_chunks) do
    receive do
      {:audio_frame, audio_binary} when is_binary(audio_binary) ->
        stream_loop(config, subscriber, [audio_binary | audio_chunks])

      :finish ->
        flush_and_emit(config, subscriber, audio_chunks)

      other ->
        Logger.warning("[STT.StreamAdapter] Unexpected message: #{inspect(other)}")
        stream_loop(config, subscriber, audio_chunks)
    end
  end

  defp flush_and_emit(config, subscriber, audio_chunks) do
    send(subscriber, {:speech_event, %SpeechEvent{type: :start}})

    combined_audio = audio_chunks |> Enum.reverse() |> IO.iodata_to_binary()

    {provider_mod, provider_cfg} = config.provider
    provider_opts = [config: provider_cfg]

    case provider_mod.transcribe(combined_audio, provider_opts) do
      {:ok, %SpeechEvent{} = event} ->
        final_event = %SpeechEvent{
          type: :final,
          text: event.text,
          confidence: event.confidence,
          language: event.language
        }

        send(subscriber, {:speech_event, final_event})

      {:error, reason} ->
        Logger.error("[STT.StreamAdapter] Batch transcription failed: #{inspect(reason)}")
        send(subscriber, {:error, reason})
    end

    send(subscriber, {:speech_event, %SpeechEvent{type: :end}})
  end
end

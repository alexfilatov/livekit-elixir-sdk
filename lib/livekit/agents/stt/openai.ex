defmodule Livekit.Agents.STT.OpenAI do
  @moduledoc """
  OpenAI speech-to-text — Whisper and the gpt-4o transcribe models.

  Pairs with `Livekit.Agents.LLM.OpenAI` and `Livekit.Agents.TTS.OpenAI`, so
  an agent can hear, think and speak on one account and one key.

  ## Batch, not streaming

  `Livekit.Agents.Pipeline` calls `transcribe/2` once a turn has ended, with
  the whole utterance buffered — it does not stream partial results. A batch
  transcription endpoint is therefore a natural fit rather than a compromise,
  and `stream/1` is deliberately not implemented.

  ## Audio format

  The pipeline carries raw PCM16 from the room; OpenAI's endpoint takes a
  *file* and rejects a bare PCM body. A 44-byte WAV header is added here.
  Doing it at the edge means the pipeline stays in one format and only the
  provider that needs a container knows about one.

      config = %OpenAI.Config{api_key: System.get_env("OPENAI_API_KEY")}
      {:ok, event} = OpenAI.transcribe(pcm16_audio, config: config)
  """

  use Livekit.Agents.STT
  require Logger

  alias Livekit.Agents.STT.SpeechEvent

  defmodule Config do
    @moduledoc """
    Configuration for the OpenAI STT provider.

    ## Fields

    - `:api_key` — OpenAI API key (required)
    - `:model` — `"gpt-4o-mini-transcribe"` (default), `"gpt-4o-transcribe"`
      or `"whisper-1"`. The mini model is half the price of the other two and
      accurate enough for conversational speech.
    - `:language` — ISO-639-1 code (default `"en"`). Naming the language is
      worth doing: it stops the model guessing, which it does badly on a
      short, noisy first utterance.
    - `:sample_rate` — sample rate of the incoming PCM (default `48_000`).
      Must match what the room produces or the audio plays back at the wrong
      speed and transcribes as nonsense.
    - `:channels` — channel count of the incoming PCM (default `1`)
    - `:base_url` — API base URL. Override for testing with Bypass.
    """

    @type t :: %__MODULE__{
            api_key: String.t() | nil,
            model: String.t(),
            language: String.t(),
            sample_rate: pos_integer(),
            channels: pos_integer(),
            base_url: String.t()
          }

    defstruct api_key: nil,
              model: "gpt-4o-mini-transcribe",
              language: "en",
              sample_rate: 48_000,
              channels: 1,
              base_url: "https://api.openai.com"
  end

  @impl Livekit.Agents.STT
  def capabilities do
    %{
      streaming: false,
      interim_results: false,
      diarization: false,
      languages: ["en", "fr", "de", "es", "it", "pt", "nl", "pl", "ru", "ja", "zh"]
    }
  end

  @impl Livekit.Agents.STT
  def validate_config(%Config{api_key: key}) when key in [nil, ""],
    do: {:error, :missing_api_key}

  def validate_config(%Config{sample_rate: sr}) when sr <= 0, do: {:error, :invalid_sample_rate}
  def validate_config(%Config{channels: c}) when c <= 0, do: {:error, :invalid_channels}
  def validate_config(%Config{}), do: :ok

  @doc """
  Transcribes a buffered utterance of raw PCM16 audio.

  Silence returns an empty final event rather than an error: a turn that
  captured nothing is ordinary, and spending a request on it would bill for
  background noise.
  """
  @impl Livekit.Agents.STT
  @spec transcribe(binary(), keyword()) :: {:ok, SpeechEvent.t()} | {:error, term()}
  def transcribe(audio, opts \\ []) do
    config = Keyword.get(opts, :config, %Config{})

    cond do
      is_nil(config.api_key) or config.api_key == "" ->
        {:error, :missing_api_key}

      byte_size(audio) == 0 ->
        {:ok, %SpeechEvent{type: :final, text: "", confidence: 0.0, language: config.language}}

      true ->
        do_transcribe(config, audio)
    end
  end

  @doc """
  Not implemented: the pipeline transcribes a completed turn rather than a
  live stream, and a half-built streaming path would be worse than an honest
  refusal.
  """
  @impl Livekit.Agents.STT
  def stream(_config), do: {:error, :not_implemented}

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp do_transcribe(%Config{} = config, audio) do
    multipart =
      Tesla.Multipart.new()
      |> Tesla.Multipart.add_file_content(wav(audio, config), "audio.wav",
        name: "file",
        headers: [{"content-type", "audio/wav"}]
      )
      |> Tesla.Multipart.add_field("model", config.model)
      |> Tesla.Multipart.add_field("language", config.language)
      |> Tesla.Multipart.add_field("response_format", "json")

    case Tesla.post(build_client(config), "/v1/audio/transcriptions", multipart) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, to_event(body, config)}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("OpenAI STT error #{status}: #{inspect(body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp to_event(body, config) do
    text = extract_text(body)

    %SpeechEvent{
      type: :final,
      text: text,
      # OpenAI returns no confidence score. Reporting 1.0 would be a lie the
      # pipeline might act on; 0.0 reads as "no transcript". This says the
      # transcript is real and its certainty is unknown.
      confidence: if(text == "", do: 0.0, else: 1.0),
      language: config.language
    }
  end

  defp extract_text(%{"text" => text}) when is_binary(text), do: String.trim(text)

  defp extract_text(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"text" => text}} when is_binary(text) -> String.trim(text)
      _ -> ""
    end
  end

  defp extract_text(_), do: ""

  # A 44-byte canonical WAV header. The endpoint identifies the format from
  # the container, so raw PCM is rejected outright with a message about the
  # file type rather than the bytes.
  defp wav(pcm, %Config{sample_rate: rate, channels: channels}) do
    bits = 16
    block_align = div(channels * bits, 8)
    byte_rate = rate * block_align
    data_size = byte_size(pcm)

    <<"RIFF", 36 + data_size::little-32, "WAVE", "fmt ", 16::little-32, 1::little-16,
      channels::little-16, rate::little-32, byte_rate::little-32, block_align::little-16,
      bits::little-16, "data", data_size::little-32, pcm::binary>>
  end

  defp build_client(%Config{api_key: key, base_url: base_url}) do
    middleware = [
      {Tesla.Middleware.BaseUrl, base_url},
      {Tesla.Middleware.Headers, [{"authorization", "Bearer #{key}"}]},
      {Tesla.Middleware.JSON, decode_content_types: ["application/json"]}
    ]

    Tesla.client(middleware, Livekit.HTTP.adapter(60_000))
  end
end

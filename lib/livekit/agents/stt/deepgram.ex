defmodule Livekit.Agents.STT.Deepgram do
  @moduledoc """
  Deepgram Speech-to-Text provider implementing `Livekit.Agents.STT`.

  Supports batch HTTP transcription via Deepgram `/v1/listen` and streaming
  WebSocket transcription (see `stream/1`).

  ## Configuration

      %Livekit.Agents.STT.Deepgram.Config{
        api_key: "your_key",
        model: "nova-2",
        language: "en-US"
      }

  ## Batch usage

      {:ok, event} = Livekit.Agents.STT.Deepgram.transcribe(audio_binary, config: config)
      # => %SpeechEvent{type: :final, text: "hello world", confidence: 0.9987}
  """

  use Livekit.Agents.STT

  require Logger

  alias Livekit.Agents.STT.DeepgramStream
  alias Livekit.Agents.STT.SpeechEvent

  # --- Config struct ---

  defmodule Config do
    @moduledoc """
    Configuration for the Deepgram STT provider.

    ## Fields

    - `:api_key` — Deepgram API key (required)
    - `:model` — Deepgram model name (default: `"nova-2"`)
    - `:language` — BCP-47 language code (default: `"en-US"`)
    - `:smart_format` — enable smart formatting (default: `true`)
    - `:punctuate` — enable punctuation (default: `true`)
    - `:diarize` — enable speaker diarization (default: `false`)
    - `:interim_results` — emit interim results in streaming mode (default: `true`)
    - `:endpointing` — enable VAD-based endpointing (default: `true`)
    - `:vad_events` — emit VAD events in streaming mode (default: `true`)
    - `:sample_rate` — audio sample rate in Hz (default: `48_000`)
    - `:encoding` — audio encoding format (default: `"linear16"`)
    - `:min_buffer_duration_ms` — minimum audio duration to accumulate before sending
      a batch request; shorter audio is buffered (default: `100`)
    - `:base_url` — override the Deepgram API base URL (default: `"https://api.deepgram.com"`);
      useful in tests to point at a Bypass server
    """

    @type t :: %__MODULE__{
            api_key: String.t() | nil,
            model: String.t(),
            language: String.t(),
            smart_format: boolean(),
            punctuate: boolean(),
            diarize: boolean(),
            interim_results: boolean(),
            endpointing: boolean(),
            vad_events: boolean(),
            sample_rate: pos_integer(),
            encoding: String.t(),
            min_buffer_duration_ms: non_neg_integer(),
            base_url: String.t()
          }

    defstruct api_key: nil,
              model: "nova-2",
              language: "en-US",
              smart_format: true,
              punctuate: true,
              diarize: false,
              interim_results: true,
              endpointing: true,
              vad_events: true,
              sample_rate: 48_000,
              encoding: "linear16",
              min_buffer_duration_ms: 100,
              base_url: "https://api.deepgram.com"
  end

  # --- STT behaviour callbacks ---

  @impl Livekit.Agents.STT
  @spec capabilities() :: %{
          streaming: boolean(),
          interim_results: boolean(),
          diarization: boolean(),
          languages: [String.t()]
        }
  def capabilities do
    %{
      streaming: true,
      interim_results: true,
      diarization: true,
      languages: ["en", "en-US", "es", "fr", "de", "ja", "ko", "pt", "ru", "zh"]
    }
  end

  @impl Livekit.Agents.STT
  @spec validate_config(Config.t()) :: :ok | {:error, term()}
  def validate_config(%Config{api_key: key}) when key in [nil, ""], do: {:error, :missing_api_key}
  def validate_config(%Config{sample_rate: sr}) when sr <= 0, do: {:error, :invalid_sample_rate}
  def validate_config(%Config{}), do: :ok

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
        do_transcribe(audio, config)
    end
  end

  @doc """
  Starts a streaming transcription session.

  Returns `{:ok, stream_pid}` where `stream_pid` is a `DeepgramStream` process
  that sends `{:speech_event, %SpeechEvent{}}` messages to the calling process.

  ## Usage

      config = %Livekit.Agents.STT.Deepgram.Config{api_key: "..."}
      {:ok, stream_pid} = Livekit.Agents.STT.Deepgram.stream(config)

      # Send audio
      Livekit.Agents.STT.DeepgramStream.send_audio(stream_pid, audio_binary)

      # Receive events
      receive do
        {:speech_event, event} -> IO.inspect(event)
      end

      # Close when done
      Livekit.Agents.STT.DeepgramStream.finish(stream_pid)
  """
  @impl Livekit.Agents.STT
  @spec stream(Config.t()) :: {:ok, pid()} | {:error, term()}
  def stream(%Config{} = config) do
    DeepgramStream.start_link({config, self()})
  end

  # --- Private helpers ---

  @spec do_transcribe(binary(), Config.t()) :: {:ok, SpeechEvent.t()} | {:error, term()}
  defp do_transcribe(audio, config) do
    client = build_http_client(config)
    query = build_query_params(config)

    case Tesla.post(client, "/v1/listen", audio, query: query) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        parse_batch_response(body, config.language)

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("Deepgram API error #{status}: #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("Deepgram HTTP error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec build_http_client(Config.t()) :: Tesla.Client.t()
  defp build_http_client(config) do
    middleware = [
      {Tesla.Middleware.BaseUrl, config.base_url},
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Token #{config.api_key}"},
         {"Content-Type", "audio/l16"}
       ]},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Logger, debug: false}
    ]

    Tesla.client(middleware, Livekit.HTTP.adapter())
  end

  @spec build_query_params(Config.t()) :: keyword()
  defp build_query_params(config) do
    [
      model: config.model,
      language: config.language,
      smart_format: config.smart_format,
      punctuate: config.punctuate,
      diarize: config.diarize,
      encoding: config.encoding,
      sample_rate: config.sample_rate
    ]
  end

  @spec parse_batch_response(map(), String.t()) :: {:ok, SpeechEvent.t()} | {:error, term()}
  defp parse_batch_response(body, language) do
    transcript =
      body
      |> get_in([
        "results",
        "channels",
        Access.at(0),
        "alternatives",
        Access.at(0),
        "transcript"
      ])
      |> then(fn t -> t || "" end)

    confidence =
      body
      |> get_in([
        "results",
        "channels",
        Access.at(0),
        "alternatives",
        Access.at(0),
        "confidence"
      ])
      |> then(fn c -> c || 0.0 end)

    event = %SpeechEvent{
      type: :final,
      text: transcript,
      confidence: confidence,
      language: language
    }

    {:ok, event}
  rescue
    err ->
      Logger.error("Failed to parse Deepgram response: #{inspect(err)}")
      {:error, {:parse_error, err}}
  end
end

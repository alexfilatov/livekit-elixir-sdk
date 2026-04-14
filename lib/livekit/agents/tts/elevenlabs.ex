defmodule Livekit.Agents.TTS.ElevenLabs do
  @moduledoc """
  ElevenLabs Text-to-Speech provider for LiveKit agents.

  Implements `Livekit.Agents.TTS` behaviour as a pure functional module (no
  GenServer). Sends HTTP POST requests to the ElevenLabs
  `/v1/text-to-speech/{voice_id}` endpoint and returns the raw audio binary.

  ## Usage

      config = %ElevenLabs.Config{
        api_key: "xi-...",
        voice_id: "21m00Tcm4TlvDq8ikWAM",
        model_id: "eleven_turbo_v2_5",
        output_format: "pcm_16000"
      }

      {:ok, audio} = ElevenLabs.synthesize("Hello, world!", config: config)

  ## Mock mode

  Set `config.mock: true` (or omit the API key) to generate a sine-wave PCM
  binary locally without making any HTTP request. Useful for tests and local
  development.

  ## Caching

  Pass a `Cache` pid via the `:cache` option to enable response caching. Cache
  keys are SHA-256 hashes of `model+voice+format+text` so the original text is
  never recoverable from the key.

      {:ok, cache} = Cache.start_link(ttl_seconds: 3600, max_entries: 500)
      {:ok, audio} = ElevenLabs.synthesize("Hello", config: config, cache: cache)

  ## Supported output formats

  ElevenLabs supports PCM at various sample rates. The `output_format` field
  accepts string identifiers such as `"pcm_16000"`, `"pcm_22050"`,
  `"pcm_24000"`, and `"pcm_44100"`. The sample rate encoded in the field name
  is used to populate `Config.sample_rate` when converting responses.

  ## Streaming (future)

  ElevenLabs provides a WebSocket streaming API. Streaming support is planned
  as a future enhancement — the `capabilities/0` callback reports
  `streaming: false` until implemented.
  """

  use Livekit.Agents.TTS
  require Logger

  alias Livekit.Agents.TTS.OpenAI.Cache

  # ---------------------------------------------------------------------------
  # Config
  # ---------------------------------------------------------------------------

  defmodule Config do
    @moduledoc "Configuration for the ElevenLabs TTS provider."

    @type t :: %__MODULE__{
            api_key: String.t() | nil,
            voice_id: String.t(),
            model_id: String.t(),
            stability: float() | nil,
            similarity_boost: float() | nil,
            output_format: String.t(),
            sample_rate: pos_integer(),
            mock: boolean(),
            base_url: String.t(),
            cache_ttl_seconds: pos_integer(),
            cache_max_entries: pos_integer()
          }

    defstruct api_key: nil,
              voice_id: "21m00Tcm4TlvDq8ikWAM",
              model_id: "eleven_turbo_v2_5",
              stability: nil,
              similarity_boost: nil,
              output_format: "pcm_16000",
              sample_rate: 16_000,
              mock: false,
              base_url: "https://api.elevenlabs.io",
              cache_ttl_seconds: 3600,
              cache_max_entries: 500
  end

  # ---------------------------------------------------------------------------
  # Behaviour callbacks
  # ---------------------------------------------------------------------------

  @doc "Returns the provider's capabilities."
  @impl true
  @spec capabilities() :: %{
          streaming: boolean(),
          voices: [String.t()],
          audio_formats: [Livekit.Agents.TTS.audio_format()],
          word_timing: boolean()
        }
  def capabilities do
    %{
      streaming: false,
      voices: [
        "21m00Tcm4TlvDq8ikWAM",
        "AZnzlk1XvdvUeBnXmlld",
        "EXAVITQu4vr4xnSDxMaL",
        "ErXwobaYiN019PkySvjV",
        "MF3mGyEYCl7XYWbV9V6O",
        "TxGEqnHWrfWFTfGW9XjX",
        "VR6AewLTigWG4xSOukaG",
        "pNInz6obpgDQGcFmaJgB",
        "yoZ06aMxZJJ28mfd3POQ",
        "z9fAnlkpzviPz146aGWa"
      ],
      audio_formats: [:pcm],
      word_timing: false
    }
  end

  @doc """
  Validates the provider configuration.

  Returns `:ok` when mock mode is active or when the API key is present and
  voice settings are within bounds. Returns `{:error, reason}` otherwise.
  """
  @impl true
  @spec validate_config(Config.t()) :: :ok | {:error, term()}
  def validate_config(%Config{mock: true}), do: :ok

  def validate_config(%Config{api_key: key}) when key in [nil, ""],
    do: {:error, :missing_api_key}

  def validate_config(%Config{voice_id: v}) when v in [nil, ""],
    do: {:error, :missing_voice_id}

  def validate_config(%Config{model_id: m}) when m in [nil, ""],
    do: {:error, :missing_model_id}

  def validate_config(%Config{} = config) do
    case validate_stability(config.stability) do
      :ok -> validate_similarity_boost(config.similarity_boost)
      error -> error
    end
  end

  @doc """
  Synthesizes `text` into an audio binary.

  ## Options

    - `:config` (required) — `%ElevenLabs.Config{}` with provider settings
    - `:voice_id` — override `config.voice_id` (string)
    - `:cache` — pid of a `Cache` process; when provided, hits are returned
      from the cache and misses are stored after synthesis

  Returns `{:ok, audio_binary}` on success or `{:error, reason}` on failure.
  """
  @impl true
  @spec synthesize(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def synthesize(text, opts \\ []) do
    config = Keyword.fetch!(opts, :config)
    voice_id = Keyword.get(opts, :voice_id, config.voice_id)
    cache_pid = Keyword.get(opts, :cache)
    effective_config = %{config | voice_id: voice_id}

    if mock_mode?(effective_config) do
      {:ok, mock_synthesize(text, effective_config)}
    else
      cache_key = build_cache_key(effective_config, text)

      case maybe_cache_get(cache_pid, cache_key) do
        {:ok, cached} ->
          Logger.debug("ElevenLabs TTS cache hit for text: #{String.slice(text, 0, 50)}")
          {:ok, cached}

        :miss ->
          synthesize_uncached(effective_config, text, cache_pid, cache_key)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp synthesize_uncached(config, text, cache_pid, cache_key) do
    case do_synthesize(config, text) do
      {:ok, audio} ->
        maybe_cache_put(cache_pid, cache_key, audio)
        {:ok, audio}

      {:error, _} = err ->
        err
    end
  end

  defp mock_mode?(%Config{mock: true}), do: true
  defp mock_mode?(%Config{api_key: nil}), do: true
  defp mock_mode?(%Config{api_key: ""}), do: true
  defp mock_mode?(_), do: false

  defp mock_synthesize(text, config) do
    estimated_duration = estimate_audio_duration(text)
    sample_count = round(estimated_duration * config.sample_rate)

    # Use a fixed base frequency for the Rachel voice; other voice IDs get 440 Hz
    frequency =
      case config.voice_id do
        "21m00Tcm4TlvDq8ikWAM" -> 349.23
        "AZnzlk1XvdvUeBnXmlld" -> 392.0
        "EXAVITQu4vr4xnSDxMaL" -> 440.0
        "ErXwobaYiN019PkySvjV" -> 493.88
        "MF3mGyEYCl7XYWbV9V6O" -> 523.25
        _ -> 440.0
      end

    if sample_count <= 0 do
      <<>>
    else
      samples =
        for i <- 0..(sample_count - 1) do
          sin_value = :math.sin(2 * :math.pi() * frequency * i / config.sample_rate)
          envelope = compute_envelope(i, sample_count)
          pcm_value = round(sin_value * envelope * 16_000)
          pcm_value = max(-32_768, min(32_767, pcm_value))
          <<pcm_value::little-signed-16>>
        end

      IO.iodata_to_binary(samples)
    end
  end

  defp estimate_audio_duration(text) do
    String.length(text) / 5 / 150 * 60
  end

  defp compute_envelope(i, sample_count) do
    cond do
      i < 1000 -> i / 1000
      i > sample_count - 1000 -> (sample_count - i) / 1000
      true -> 1.0
    end
  end

  defp do_synthesize(%Config{} = config, text) do
    client = build_client(config)
    path = "/v1/text-to-speech/#{config.voice_id}"

    body = build_request_body(config, text)

    case Tesla.post(client, path, body) do
      {:ok, %{status: 200, body: audio_binary}} when is_binary(audio_binary) ->
        {:ok, audio_binary}

      {:ok, %{status: 200, body: body}} ->
        Logger.error("ElevenLabs TTS returned unexpected body type: #{inspect(body)}")
        {:error, :unexpected_response}

      {:ok, %{status: status, body: resp_body}} ->
        Logger.error("ElevenLabs TTS API error #{status}: #{inspect(resp_body)}")
        {:error, {:api_error, status, resp_body}}

      {:error, reason} ->
        Logger.error("ElevenLabs TTS request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_request_body(%Config{} = config, text) do
    voice_settings = build_voice_settings(config)

    body = %{
      text: text,
      model_id: config.model_id
    }

    if map_size(voice_settings) > 0 do
      Map.put(body, :voice_settings, voice_settings)
    else
      body
    end
  end

  defp build_voice_settings(%Config{stability: stability, similarity_boost: similarity_boost}) do
    %{}
    |> maybe_put(:stability, stability)
    |> maybe_put(:similarity_boost, similarity_boost)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp build_client(%Config{api_key: key, base_url: base_url, output_format: output_format}) do
    middleware = [
      {Tesla.Middleware.BaseUrl, base_url},
      {Tesla.Middleware.Headers,
       [
         {"xi-api-key", key},
         {"Content-Type", "application/json"},
         {"Accept", "audio/mpeg"}
       ]},
      {Tesla.Middleware.JSON,
       decode_content_types: ["application/json"], encode_content_type: "application/json"},
      {Tesla.Middleware.Query, [output_format: output_format]}
    ]

    Tesla.client(middleware, Tesla.Adapter.Hackney)
  end

  defp build_cache_key(config, text) do
    key_data = "#{config.model_id}_#{config.voice_id}_#{config.output_format}_#{text}"
    :crypto.hash(:sha256, key_data) |> Base.encode16(case: :lower)
  end

  defp maybe_cache_get(nil, _key), do: :miss
  defp maybe_cache_get(cache_pid, key), do: Cache.get(cache_pid, key)

  defp maybe_cache_put(nil, _key, _value), do: :ok
  defp maybe_cache_put(cache_pid, key, value), do: Cache.put(cache_pid, key, value)

  defp validate_stability(nil), do: :ok

  defp validate_stability(s) when s >= 0.0 and s <= 1.0, do: :ok

  defp validate_stability(_), do: {:error, :invalid_stability}

  defp validate_similarity_boost(nil), do: :ok

  defp validate_similarity_boost(s) when s >= 0.0 and s <= 1.0, do: :ok

  defp validate_similarity_boost(_), do: {:error, :invalid_similarity_boost}
end

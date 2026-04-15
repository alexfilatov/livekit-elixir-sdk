defmodule Livekit.Agents.TTS.OpenAI do
  @moduledoc """
  OpenAI Text-to-Speech provider for LiveKit agents.

  Implements `Livekit.Agents.TTS` behaviour as a pure functional module (no
  GenServer). Sends HTTP POST requests to the OpenAI `/v1/audio/speech` endpoint
  and returns the raw audio binary.

  ## Usage

      config = %OpenAI.Config{api_key: "sk-...", voice: :nova, response_format: :pcm}

      {:ok, audio} = OpenAI.synthesize("Hello, world!", config: config)

  ## Caching

  Pass a `Cache` pid via the `:cache` option to enable response caching.  Cache
  keys are SHA-256 hashes of `model+voice+speed+format+text` so the original
  text is never recoverable from the key.

      {:ok, cache} = Cache.start_link(ttl_seconds: 3600, max_entries: 500)
      {:ok, audio} = OpenAI.synthesize("Hello", config: config, cache: cache)
  """

  use Livekit.Agents.TTS
  require Logger

  alias Livekit.Agents.TTS.OpenAI.Cache

  # ---------------------------------------------------------------------------
  # Config
  # ---------------------------------------------------------------------------

  defmodule Config do
    @moduledoc "Configuration for the OpenAI TTS provider."

    @type voice :: :alloy | :echo | :fable | :onyx | :nova | :shimmer
    @type model :: :tts_1 | :tts_1_hd
    @type response_format :: :mp3 | :opus | :aac | :flac | :pcm

    @type t :: %__MODULE__{
            api_key: String.t() | nil,
            model: model(),
            voice: voice(),
            response_format: response_format(),
            speed: float(),
            sample_rate: pos_integer(),
            base_url: String.t(),
            cache_ttl_seconds: pos_integer(),
            cache_max_entries: pos_integer()
          }

    defstruct api_key: nil,
              model: :tts_1,
              voice: :alloy,
              response_format: :pcm,
              speed: 1.0,
              sample_rate: 48_000,
              base_url: "https://api.openai.com",
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
      voices: ["alloy", "echo", "fable", "onyx", "nova", "shimmer"],
      audio_formats: [:pcm, :mp3, :opus, :aac, :flac],
      word_timing: false
    }
  end

  @doc """
  Validates the provider configuration.

  Returns `{:error, :missing_api_key}` when the API key is absent or empty.
  Returns `{:error, reason}` when speed or sample_rate are out of bounds.
  Returns `:ok` when all values are valid.
  """
  @impl true
  @spec validate_config(Config.t()) :: :ok | {:error, term()}
  def validate_config(config) do
    cond do
      is_nil(config.api_key) or config.api_key == "" -> {:error, :missing_api_key}
      config.speed < 0.25 or config.speed > 4.0 -> {:error, :invalid_speed}
      config.sample_rate <= 0 -> {:error, :invalid_sample_rate}
      true -> :ok
    end
  end

  @doc """
  Synthesizes `text` into an audio binary.

  ## Options

    - `:config` (required) — `%OpenAI.Config{}` with provider settings
    - `:voice` — override `config.voice` (atom, e.g. `:alloy`)
    - `:format` — override `config.response_format` (atom, e.g. `:mp3`)
    - `:cache` — pid of a `Cache` process; when provided, hits are returned
      from the cache and misses are stored after synthesis

  Returns `{:ok, audio_binary}` on success or `{:error, reason}` on failure.
  """
  @impl true
  @spec synthesize(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def synthesize(text, opts \\ []) do
    config = Keyword.fetch!(opts, :config)
    voice = Keyword.get(opts, :voice, config.voice)
    format = Keyword.get(opts, :format, config.response_format)
    cache_pid = Keyword.get(opts, :cache)
    effective_config = %{config | voice: voice, response_format: format}

    cache_key = build_cache_key(effective_config, text)

    case maybe_cache_get(cache_pid, cache_key) do
      {:ok, cached} ->
        Logger.debug("TTS cache hit for text: #{String.slice(text, 0, 50)}")
        {:ok, cached}

      :miss ->
        synthesize_uncached(effective_config, text, cache_pid, cache_key)
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

  defp do_synthesize(%Config{} = config, text) do
    client = build_client(config)

    body = %{
      model: config.model |> Atom.to_string() |> String.replace("_", "-"),
      input: text,
      voice: Atom.to_string(config.voice),
      response_format: Atom.to_string(config.response_format),
      speed: config.speed
    }

    case Tesla.post(client, "/v1/audio/speech", body) do
      {:ok, %{status: 200, body: audio_binary}} ->
        {:ok, audio_binary}

      {:ok, %{status: status, body: resp_body}} ->
        Logger.error("OpenAI TTS API error #{status}: #{inspect(resp_body)}")
        {:error, {:api_error, status, resp_body}}

      {:error, reason} ->
        Logger.error("OpenAI TTS request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_client(%Config{api_key: key, base_url: base_url}) do
    middleware = [
      {Tesla.Middleware.BaseUrl, base_url},
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Bearer #{key}"},
         {"Content-Type", "application/json"}
       ]},
      {Tesla.Middleware.JSON, decode_content_types: ["application/json"]}
    ]

    Tesla.client(middleware, Tesla.Adapter.Hackney)
  end

  defp build_cache_key(config, text) do
    key_data =
      "#{config.model}_#{config.voice}_#{config.speed}_#{config.response_format}_#{text}"

    :crypto.hash(:sha256, key_data) |> Base.encode16(case: :lower)
  end

  defp maybe_cache_get(nil, _key), do: :miss
  defp maybe_cache_get(cache_pid, key), do: Cache.get(cache_pid, key)

  defp maybe_cache_put(nil, _key, _value), do: :ok
  defp maybe_cache_put(cache_pid, key, value), do: Cache.put(cache_pid, key, value)
end

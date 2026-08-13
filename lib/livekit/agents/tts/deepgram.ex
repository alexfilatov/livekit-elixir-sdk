defmodule Livekit.Agents.TTS.Deepgram do
  @moduledoc """
  Deepgram text-to-speech (Aura and Flux voices).

  Pairs with `Livekit.Agents.STT.Deepgram`, so an agent can do both the ear
  and the voice on one account and one key.

  ## Endpoint versions

  Deepgram serves Aura voices from `/v1/speak` and Flux voices from
  `/v2/speak`, and asking the wrong one returns
  `V2_MODEL_ON_V1_SPEAK_ENDPOINT` rather than working. The version is chosen
  from the model name so callers do not have to know this.

  ## Audio format

  Defaults to raw 48 kHz PCM16 (`encoding=linear16`, `container=none`) because
  that is what `Livekit.Agents.Pipeline` feeds into a room. Without
  `container=none` Deepgram wraps the audio in a WAV header, and the RIFF
  bytes arrive as a burst of noise at the start of every utterance.

      config = %Deepgram.Config{api_key: System.get_env("DEEPGRAM_API_KEY")}
      {:ok, audio} = Deepgram.synthesize("Hello.", config: config)
  """

  use Livekit.Agents.TTS
  require Logger

  # Aura is /v1; Flux is /v2. Matched on the model name prefix.
  @flux_prefix "flux-"

  defmodule Config do
    @moduledoc """
    Configuration for the Deepgram TTS provider.

    ## Fields

    - `:api_key` — Deepgram API key (required)
    - `:model` — voice model name (default `"aura-2-thalia-en"`, Deepgram's own
      default). Any Aura or Flux voice is valid; the endpoint version is
      derived from the name. Note the price difference: Aura-1 is
      $0.015/1k characters, Aura-2 $0.030, Flux $0.045 — for a voice agent,
      TTS dominates the bill, so this field is worth choosing deliberately.
    - `:encoding` — audio encoding (default `"linear16"`)
    - `:sample_rate` — output sample rate in Hz (default `48_000`)
    - `:container` — container format; `"none"` for raw PCM (default `"none"`)
    - `:base_url` — API base URL. Override for testing with Bypass.
    """

    @type t :: %__MODULE__{
            api_key: String.t() | nil,
            model: String.t(),
            encoding: String.t(),
            sample_rate: pos_integer(),
            container: String.t(),
            base_url: String.t()
          }

    defstruct api_key: nil,
              model: "aura-2-thalia-en",
              encoding: "linear16",
              sample_rate: 48_000,
              container: "none",
              base_url: "https://api.deepgram.com"
  end

  @impl Livekit.Agents.TTS
  def capabilities do
    %{
      streaming: false,
      # The British voices, which is what this is here for. Deepgram publishes
      # ~94 Aura voices besides these; any of them is a valid :model.
      # A sample, not the whole catalogue: Deepgram publishes ~94 Aura voices
      # plus the Flux set, and any of them is a valid :model.
      voices: ["aura-2-thalia-en", "aura-2-draco-en", "aura-helios-en", "flux-colin-en"],
      formats: [:pcm16]
    }
  end

  @impl Livekit.Agents.TTS
  def validate_config(%Config{api_key: key}) when key in [nil, ""],
    do: {:error, :missing_api_key}

  def validate_config(%Config{model: m}) when m in [nil, ""], do: {:error, :missing_model}
  def validate_config(%Config{sample_rate: sr}) when sr <= 0, do: {:error, :invalid_sample_rate}
  def validate_config(%Config{}), do: :ok

  @doc """
  Synthesizes `text`, returning the audio binary.

  Empty text short-circuits to empty audio rather than spending a request:
  a pipeline turn that produced nothing to say is normal, not an error.
  """
  @impl Livekit.Agents.TTS
  @spec synthesize(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def synthesize(text, opts \\ []) do
    config = Keyword.fetch!(opts, :config)

    cond do
      is_nil(config.api_key) or config.api_key == "" -> {:error, :missing_api_key}
      String.trim(text) == "" -> {:ok, <<>>}
      true -> do_synthesize(config, text)
    end
  end

  @impl Livekit.Agents.TTS
  def stream(_config), do: {:error, :not_implemented}

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp do_synthesize(%Config{} = config, text) do
    query = [
      model: config.model,
      encoding: config.encoding,
      sample_rate: config.sample_rate,
      container: config.container
    ]

    case Tesla.post(build_client(config), speak_path(config.model), %{text: text}, query: query) do
      {:ok, %Tesla.Env{status: 200, body: audio}} when is_binary(audio) ->
        {:ok, audio}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("Deepgram TTS error #{status}: #{inspect(body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  # Asking /v1 for a Flux voice fails with a dedicated error code rather than
  # falling back, so the version is derived rather than configured.
  defp speak_path(@flux_prefix <> _), do: "/v2/speak"
  defp speak_path(_model), do: "/v1/speak"

  defp build_client(%Config{api_key: key, base_url: base_url}) do
    middleware = [
      {Tesla.Middleware.BaseUrl, base_url},
      {Tesla.Middleware.Headers,
       [{"authorization", "Token #{key}"}, {"content-type", "application/json"}]},
      # Encode the request as JSON but leave the RESPONSE alone: it is audio,
      # and a JSON decoder would either mangle it or fail on the first byte.
      Tesla.Middleware.EncodeJson
    ]

    Tesla.client(middleware, Livekit.HTTP.adapter(30_000))
  end
end

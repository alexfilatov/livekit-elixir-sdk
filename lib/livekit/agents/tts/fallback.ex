defmodule Livekit.Agents.TTS.Fallback do
  @moduledoc """
  Fallback adapter for TTS providers.

  Tries the primary provider first. If the primary returns `{:error, _}`, it
  automatically switches to the secondary provider and logs the failover event.

  Both providers are configured as `{module, config}` tuples, matching the
  standard provider injection pattern.

  ## Usage

      primary = {Livekit.Agents.TTS.OpenAI, %OpenAI.Config{api_key: "key1"}}
      secondary = {Livekit.Agents.TTS.ElevenLabs, %ElevenLabs.Config{api_key: "key2"}}

      config = %Livekit.Agents.TTS.Fallback.Config{
        primary: primary,
        secondary: secondary
      }

      {:ok, audio} = Livekit.Agents.TTS.Fallback.synthesize("Hello!", config: config)

  ## Streaming

  If the primary provider supports streaming via `stream/1`, the adapter will
  delegate to it. On failure, it falls back to the secondary.
  """

  use Livekit.Agents.TTS

  require Logger

  # ---------------------------------------------------------------------------
  # Config
  # ---------------------------------------------------------------------------

  defmodule Config do
    @moduledoc """
    Configuration for the TTS Fallback adapter.

    ## Fields

    - `:primary` — `{module, config}` tuple for the primary TTS provider (required)
    - `:secondary` — `{module, config}` tuple for the secondary TTS provider (required)
    """

    @type provider :: {module(), map()}

    @type t :: %__MODULE__{
            primary: provider(),
            secondary: provider()
          }

    defstruct primary: nil, secondary: nil
  end

  # ---------------------------------------------------------------------------
  # Behaviour callbacks
  # ---------------------------------------------------------------------------

  @doc "Returns capability map for the fallback adapter."
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
  Validates the fallback config. Both `:primary` and `:secondary` must be present.
  """
  @impl Livekit.Agents.TTS
  @spec validate_config(Config.t()) :: :ok | {:error, term()}
  def validate_config(%Config{primary: nil}), do: {:error, :missing_primary}
  def validate_config(%Config{secondary: nil}), do: {:error, :missing_secondary}
  def validate_config(%Config{primary: {_mod, _cfg}, secondary: {_mod2, _cfg2}}), do: :ok

  @doc """
  Synthesizes text with automatic failover.

  Calls the primary provider first. On `{:error, _}`, logs the failover event
  and delegates to the secondary provider.

  ## Options

    - `:config` (required) — `%Fallback.Config{}` with primary/secondary tuples
    - Any other options are forwarded to both providers
  """
  @impl Livekit.Agents.TTS
  @spec synthesize(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def synthesize(text, opts \\ []) do
    config = Keyword.fetch!(opts, :config)
    {primary_mod, primary_cfg} = config.primary
    {secondary_mod, secondary_cfg} = config.secondary

    provider_opts = Keyword.put(Keyword.delete(opts, :config), :config, primary_cfg)

    case primary_mod.synthesize(text, provider_opts) do
      {:ok, _} = result ->
        result

      {:error, reason} ->
        Logger.warning(
          "[TTS.Fallback] Primary provider #{inspect(primary_mod)} failed: #{inspect(reason)}. " <>
            "Failing over to #{inspect(secondary_mod)}."
        )

        secondary_opts = Keyword.put(Keyword.delete(opts, :config), :config, secondary_cfg)
        secondary_mod.synthesize(text, secondary_opts)
    end
  end

  @doc """
  Starts a streaming synthesis session with automatic failover.

  Attempts to start a stream on the primary provider. If the primary fails or
  does not support streaming, falls back to the secondary.

  ## Options

  `config` must be a `%Fallback.Config{}` with `:primary` and `:secondary` set.
  """
  @impl Livekit.Agents.TTS
  @spec stream(Config.t()) :: {:ok, pid()} | {:error, term()}
  def stream(%Config{} = config) do
    {primary_mod, primary_cfg} = config.primary
    {secondary_mod, secondary_cfg} = config.secondary

    if function_exported?(primary_mod, :stream, 1) do
      tts_stream_with_primary_fallback(primary_mod, primary_cfg, secondary_mod, secondary_cfg)
    else
      Logger.warning(
        "[TTS.Fallback] Primary #{inspect(primary_mod)} does not support streaming. " <>
          "Falling over to #{inspect(secondary_mod)}."
      )

      tts_stream_via_secondary(secondary_mod, secondary_cfg, :no_provider_supports_streaming)
    end
  end

  defp tts_stream_with_primary_fallback(primary_mod, primary_cfg, secondary_mod, secondary_cfg) do
    case primary_mod.stream(primary_cfg) do
      {:ok, _} = result ->
        result

      {:error, reason} ->
        Logger.warning(
          "[TTS.Fallback] Primary stream #{inspect(primary_mod)} failed: #{inspect(reason)}. " <>
            "Failing over to #{inspect(secondary_mod)}."
        )

        tts_stream_via_secondary(secondary_mod, secondary_cfg, :secondary_does_not_support_streaming)
    end
  end

  defp tts_stream_via_secondary(secondary_mod, secondary_cfg, error_atom) do
    if function_exported?(secondary_mod, :stream, 1) do
      secondary_mod.stream(secondary_cfg)
    else
      {:error, error_atom}
    end
  end
end

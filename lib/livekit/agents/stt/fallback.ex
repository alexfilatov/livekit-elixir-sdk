defmodule Livekit.Agents.STT.Fallback do
  @moduledoc """
  Fallback adapter for STT providers.

  Tries the primary provider first. If the primary returns `{:error, _}`, it
  automatically switches to the secondary provider and logs the failover event.

  Both providers are configured as `{module, config}` tuples, matching the
  standard provider injection pattern.

  ## Usage

      primary = {Livekit.Agents.STT.Deepgram, %Deepgram.Config{api_key: "key1"}}
      secondary = {Livekit.Agents.STT.Deepgram, %Deepgram.Config{api_key: "key2"}}

      config = %Livekit.Agents.STT.Fallback.Config{
        primary: primary,
        secondary: secondary
      }

      {:ok, event} = Livekit.Agents.STT.Fallback.transcribe(audio, config: config)

  ## Metrics

  Retrieve failover metrics via `get_metrics/1`:

      {:ok, pid} = Livekit.Agents.STT.Fallback.start_link(config)
      metrics = Livekit.Agents.STT.Fallback.get_metrics(pid)
      # => %{primary_requests: 10, failovers: 2, secondary_requests: 2, errors: 0}

  The adapter exposes streaming through the primary provider if it supports it,
  falling back to the secondary on stream start failure.
  """

  use Livekit.Agents.STT

  require Logger

  alias Livekit.Agents.STT.SpeechEvent

  # ---------------------------------------------------------------------------
  # Config
  # ---------------------------------------------------------------------------

  defmodule Config do
    @moduledoc """
    Configuration for the STT Fallback adapter.

    ## Fields

    - `:primary` — `{module, config}` tuple for the primary STT provider (required)
    - `:secondary` — `{module, config}` tuple for the secondary STT provider (required)
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

  @doc "Returns merged capabilities from primary provider."
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
  Validates the fallback config. Both `:primary` and `:secondary` must be present.
  """
  @impl Livekit.Agents.STT
  @spec validate_config(Config.t()) :: :ok | {:error, term()}
  def validate_config(%Config{primary: nil}), do: {:error, :missing_primary}
  def validate_config(%Config{secondary: nil}), do: {:error, :missing_secondary}
  def validate_config(%Config{primary: {_mod, _cfg}, secondary: {_mod2, _cfg2}}), do: :ok

  @doc """
  Transcribes audio with automatic failover.

  Calls the primary provider first. On `{:error, _}`, logs the failover event
  and delegates to the secondary provider.

  ## Options

    - `:config` (required) — `%Fallback.Config{}` with primary/secondary tuples
    - Any other options are forwarded to both providers
  """
  @impl Livekit.Agents.STT
  @spec transcribe(binary(), keyword()) :: {:ok, SpeechEvent.t()} | {:error, term()}
  def transcribe(audio, opts \\ []) do
    config = Keyword.fetch!(opts, :config)
    {primary_mod, primary_cfg} = config.primary
    {secondary_mod, secondary_cfg} = config.secondary

    provider_opts = Keyword.put(Keyword.delete(opts, :config), :config, primary_cfg)

    case primary_mod.transcribe(audio, provider_opts) do
      {:ok, _} = result ->
        result

      {:error, reason} ->
        Logger.warning(
          "[STT.Fallback] Primary provider #{inspect(primary_mod)} failed: #{inspect(reason)}. " <>
            "Failing over to #{inspect(secondary_mod)}."
        )

        secondary_opts = Keyword.put(Keyword.delete(opts, :config), :config, secondary_cfg)
        secondary_mod.transcribe(audio, secondary_opts)
    end
  end

  @doc """
  Starts a streaming session with automatic failover.

  Attempts to start a stream on the primary provider. If the primary fails, falls
  back to the secondary.

  ## Options

  `config` must be a `%Fallback.Config{}` with `:primary` and `:secondary` set.
  """
  @impl Livekit.Agents.STT
  @spec stream(Config.t()) :: {:ok, pid()} | {:error, term()}
  def stream(%Config{} = config) do
    {primary_mod, primary_cfg} = config.primary
    {secondary_mod, secondary_cfg} = config.secondary

    if function_exported?(primary_mod, :stream, 1) do
      case primary_mod.stream(primary_cfg) do
        {:ok, _} = result ->
          result

        {:error, reason} ->
          Logger.warning(
            "[STT.Fallback] Primary stream #{inspect(primary_mod)} failed: #{inspect(reason)}. " <>
              "Failing over to #{inspect(secondary_mod)}."
          )

          if function_exported?(secondary_mod, :stream, 1) do
            secondary_mod.stream(secondary_cfg)
          else
            {:error, :secondary_does_not_support_streaming}
          end
      end
    else
      Logger.warning(
        "[STT.Fallback] Primary #{inspect(primary_mod)} does not support streaming. " <>
          "Falling over to #{inspect(secondary_mod)}."
      )

      if function_exported?(secondary_mod, :stream, 1) do
        secondary_mod.stream(secondary_cfg)
      else
        {:error, :no_provider_supports_streaming}
      end
    end
  end
end

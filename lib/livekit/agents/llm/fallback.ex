defmodule Livekit.Agents.LLM.Fallback do
  @moduledoc """
  Fallback adapter for LLM providers.

  Tries the primary provider first. If the primary returns `{:error, _}`, it
  automatically switches to the secondary provider and logs the failover event.

  Both providers are configured as `{module, config}` tuples, matching the
  standard provider injection pattern.

  ## Usage

      primary = {Livekit.Agents.LLM.OpenAI, %OpenAI.Config{api_key: "key1"}}
      secondary = {Livekit.Agents.LLM.Anthropic, %Anthropic.Config{api_key: "key2"}}

      config = %Livekit.Agents.LLM.Fallback.Config{
        primary: primary,
        secondary: secondary
      }

      {:ok, message} = Livekit.Agents.LLM.Fallback.chat(ctx, config: config)

  ## Streaming

  If the primary provider supports streaming via `stream/2`, the adapter will
  delegate to it. On failure, it falls back to the secondary.
  """

  use Livekit.Agents.LLM

  require Logger

  # ---------------------------------------------------------------------------
  # Config
  # ---------------------------------------------------------------------------

  defmodule Config do
    @moduledoc """
    Configuration for the LLM Fallback adapter.

    ## Fields

    - `:primary` — `{module, config}` tuple for the primary LLM provider (required)
    - `:secondary` — `{module, config}` tuple for the secondary LLM provider (required)
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
  @impl Livekit.Agents.LLM
  @spec capabilities() :: %{
          streaming: boolean(),
          tool_calling: boolean(),
          vision: boolean(),
          max_context_tokens: pos_integer() | nil
        }
  def capabilities do
    %{streaming: true, tool_calling: false, vision: false, max_context_tokens: nil}
  end

  @doc """
  Validates the fallback config. Both `:primary` and `:secondary` must be present.
  """
  @impl Livekit.Agents.LLM
  @spec validate_config(Config.t()) :: :ok | {:error, term()}
  def validate_config(%Config{primary: nil}), do: {:error, :missing_primary}
  def validate_config(%Config{secondary: nil}), do: {:error, :missing_secondary}
  def validate_config(%Config{primary: {_mod, _cfg}, secondary: {_mod2, _cfg2}}), do: :ok

  @doc """
  Sends a chat context with automatic failover.

  Calls the primary provider first. On `{:error, _}`, logs the failover event
  and delegates to the secondary provider.

  ## Options

    - `:config` (required) — `%Fallback.Config{}` with primary/secondary tuples
    - Any other options are forwarded to both providers
  """
  @impl Livekit.Agents.LLM
  @spec chat(Livekit.Agents.LLM.chat_context(), keyword()) ::
          {:ok, Livekit.Agents.LLM.chat_message()} | {:error, term()}
  def chat(ctx, opts \\ []) do
    config = Keyword.fetch!(opts, :config)
    {primary_mod, primary_cfg} = config.primary
    {secondary_mod, secondary_cfg} = config.secondary

    provider_opts = Keyword.put(Keyword.delete(opts, :config), :config, primary_cfg)

    case primary_mod.chat(ctx, provider_opts) do
      {:ok, _} = result ->
        result

      {:error, reason} ->
        Logger.warning(
          "[LLM.Fallback] Primary provider #{inspect(primary_mod)} failed: #{inspect(reason)}. " <>
            "Failing over to #{inspect(secondary_mod)}."
        )

        secondary_opts = Keyword.put(Keyword.delete(opts, :config), :config, secondary_cfg)
        secondary_mod.chat(ctx, secondary_opts)
    end
  end

  @doc """
  Starts a streaming LLM response with automatic failover.

  Attempts to start a stream on the primary provider. If the primary fails or
  does not support streaming, falls back to the secondary.

  ## Options

    - `:config` (required) — `%Fallback.Config{}` with primary/secondary tuples
    - Any other options are forwarded to both providers
  """
  @impl Livekit.Agents.LLM
  @spec stream(Livekit.Agents.LLM.chat_context(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def stream(ctx, opts \\ []) do
    config = Keyword.fetch!(opts, :config)
    {primary_mod, primary_cfg} = config.primary
    {secondary_mod, secondary_cfg} = config.secondary

    if function_exported?(primary_mod, :stream, 2) do
      provider_opts = Keyword.put(Keyword.delete(opts, :config), :config, primary_cfg)

      case primary_mod.stream(ctx, provider_opts) do
        {:ok, _} = result ->
          result

        {:error, reason} ->
          Logger.warning(
            "[LLM.Fallback] Primary stream #{inspect(primary_mod)} failed: #{inspect(reason)}. " <>
              "Failing over to #{inspect(secondary_mod)}."
          )

          if function_exported?(secondary_mod, :stream, 2) do
            secondary_opts = Keyword.put(Keyword.delete(opts, :config), :config, secondary_cfg)
            secondary_mod.stream(ctx, secondary_opts)
          else
            {:error, :secondary_does_not_support_streaming}
          end
      end
    else
      Logger.warning(
        "[LLM.Fallback] Primary #{inspect(primary_mod)} does not support streaming. " <>
          "Falling over to #{inspect(secondary_mod)}."
      )

      if function_exported?(secondary_mod, :stream, 2) do
        secondary_opts = Keyword.put(Keyword.delete(opts, :config), :config, secondary_cfg)
        secondary_mod.stream(ctx, secondary_opts)
      else
        {:error, :no_provider_supports_streaming}
      end
    end
  end
end

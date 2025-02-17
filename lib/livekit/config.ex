defmodule LiveKit.Config do
  @moduledoc """
  Configuration module for LiveKit.
  Handles configuration management and provides a unified interface for accessing LiveKit settings.
  """

  @type t :: %__MODULE__{
          url: String.t(),
          api_key: String.t(),
          api_secret: String.t()
        }

  defstruct [:url, :api_key, :api_secret]

  @doc """
  Returns the current configuration. It merges the following in order of precedence:
  1. Runtime-provided options (highest priority)
  2. Application environment
  3. Environment variables
  4. Default values (lowest priority)
  """
  @spec get(keyword()) :: t()
  def get(opts \\ []) do
    app_config = Application.get_all_env(:livekit)

    %__MODULE__{
      url: get_config_value(:url, opts, app_config),
      api_key: get_config_value(:api_key, opts, app_config),
      api_secret: get_config_value(:api_secret, opts, app_config)
    }
  end

  @doc """
  Validates the configuration and returns :ok if valid, {:error, reason} otherwise.
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{} = config) do
    cond do
      is_nil(config.url) or config.url == "" ->
        {:error, "LiveKit URL is required"}

      is_nil(config.api_key) or config.api_key == "" ->
        {:error, "LiveKit API key is required"}

      is_nil(config.api_secret) or config.api_secret == "" ->
        {:error, "LiveKit API secret is required"}

      true ->
        :ok
    end
  end

  @doc """
  Returns a validated configuration or an error.
  """
  @spec get_validated(keyword()) :: {:ok, t()} | {:error, String.t()}
  def get_validated(opts \\ []) do
    config = get(opts)

    case validate(config) do
      :ok -> {:ok, config}
      error -> error
    end
  end

  # Private Helpers

  defp get_config_value(key, opts, app_config) do
    Keyword.get(opts, key) ||
      Keyword.get(app_config, key) ||
      System.get_env("LIVEKIT_#{key |> to_string() |> String.upcase()}")
  end
end

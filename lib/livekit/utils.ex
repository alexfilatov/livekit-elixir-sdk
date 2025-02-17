defmodule Livekit.Utils do
  @moduledoc """
  Utility functions for Livekit SDK.
  """

  @doc """
  Converts a URL to an HTTP URL if it's not already.
  """
  def to_http_url(url) when is_binary(url) do
    uri = URI.parse(url)

    case uri.scheme do
      nil -> "http://" <> url
      "ws" -> "http://" <> String.replace_prefix(url, "ws://", "")
      "wss" -> "https://" <> String.replace_prefix(url, "wss://", "")
      _ -> url
    end
  end

  @doc """
  Generates a random string of specified length.
  """
  def random_string(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.url_encode64()
    |> binary_part(0, length)
  end
end

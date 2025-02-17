defmodule Livekit.TokenVerifier do
  @moduledoc """
  Verifies Livekit access tokens.
  """

  @doc """
  Verifies a JWT token with the given API secret.
  """
  def verify(token, api_secret) when is_binary(token) and is_binary(api_secret) do
    signer = Joken.Signer.create("HS256", api_secret)

    case Joken.verify(token, signer) do
      {:ok, claims} ->
        {:ok, claims}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Verifies a JWT token and returns the claims if valid, raises an error otherwise.
  """
  def verify!(token, api_secret) when is_binary(token) and is_binary(api_secret) do
    case verify(token, api_secret) do
      {:ok, claims} -> claims
      {:error, reason} -> raise "Invalid token: #{inspect(reason)}"
    end
  end
end

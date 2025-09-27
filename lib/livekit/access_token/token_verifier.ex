defmodule Livekit.AccessToken.TokenVerifier do
  @moduledoc """
  Verifies Livekit access tokens.
  """

  @doc """
  Verifies a JWT token with the given API secret.
  """
  @spec verify(token :: binary(), api_secret :: binary()) ::
          {:ok, map()} | {:error, Joken.error_reason()}
  def verify(token, api_secret) when is_binary(token) and is_binary(api_secret) do
    signer = Joken.Signer.create("HS256", api_secret)

    # TO DO: recreate access token from claims
    case Joken.verify(token, signer) do
      {:ok, claims} ->
        {:ok, parse_claims(claims)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Verifies a JWT token with the given API secret and API key.

  ## Parameters

  - `token`: The JWT token to verify
  - `api_key`: The API key to verify against
  - `api_secret`: The API secret to verify with

  ## Returns

  - `{:ok, claims}`: If the token is valid, returns the decoded claims
  - `{:error, reason}`: If the token is invalid
  """
  @spec verify_with_issuer(token :: binary(), api_key :: binary(), api_secret :: binary()) ::
          {:ok, map()} | {:error, Joken.error_reason()} | {:error, :invalid_issuer}
  def verify_with_issuer(token, api_key, api_secret)
      when is_binary(token) and is_binary(api_key) and is_binary(api_secret) do
    case verify(token, api_secret) do
      {:ok, claims} ->
        # Verify that the issuer matches the API key
        if claims["iss"] == api_key do
          {:ok, claims}
        else
          {:error, :invalid_issuer}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Verifies a JWT token and returns the claims if valid, raises an error otherwise.
  """
  @spec verify!(token :: binary(), api_secret :: binary()) :: map() | no_return()
  def verify!(token, api_secret) when is_binary(token) and is_binary(api_secret) do
    case verify(token, api_secret) do
      {:ok, claims} -> claims
      {:error, reason} -> raise "Invalid token: #{inspect(reason)}"
    end
  end

  @spec parse_claims(claims :: map()) :: map()
  defp parse_claims(claims) do
    Map.new(claims, fn {k, v} ->
      if is_map(v) do
        {camel_to_snake(k), parse_claims(v)}
      else
        {camel_to_snake(k), v}
      end
    end)
  end

  @spec camel_to_snake(value :: String.t()) :: String.t()
  defp camel_to_snake(value), do: Inflex.underscore(value)
end

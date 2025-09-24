defmodule Livekit.AccessToken do
  @moduledoc """
  Handles generation and management of Livekit access tokens.
  """

  alias Livekit.Grants

  defstruct api_key: nil,
            api_secret: nil,
            grants: %Grants{},
            identity: nil,
            name: nil,
            ttl: nil,
            metadata: nil

  @type t :: %__MODULE__{
          api_key: String.t() | nil,
          api_secret: String.t() | nil,
          grants: Grants.t(),
          identity: String.t() | nil,
          name: String.t() | nil,
          ttl: integer() | nil,
          metadata: String.t() | nil
        }

  @doc """
  Creates a new AccessToken with the given API key and secret.
  """
  def new(api_key, api_secret) do
    %__MODULE__{
      api_key: api_key,
      api_secret: api_secret
    }
  end

  @doc """
  Sets the identity for the token.
  """
  def with_identity(%__MODULE__{} = token, identity) do
    %{token | identity: identity}
  end

  @doc """
  Sets the TTL (time to live) for the token in seconds.
  """
  def with_ttl(%__MODULE__{} = token, ttl) when is_integer(ttl) do
    %{token | ttl: ttl}
  end

  @doc """
  Sets metadata for the token.
  """
  def with_metadata(%__MODULE__{} = token, metadata) do
    %{token | metadata: metadata}
  end

  @doc """
  Sets the name for the token.
  """
  def with_name(%__MODULE__{} = token, name) do
    %{token | name: name}
  end

  @doc """
  Sets the grants for the token.
  """
  def with_grants(%__MODULE__{} = token, %Livekit.Grants{} = grants) do
    %{token | grants: grants}
  end

  @doc """
  Adds a grant to the token.
  """
  def add_grant(%__MODULE__{} = token, grant) do
    %{token | grants: Map.merge(token.grants, grant)}
  end

  @doc """
  Generates a JWT token string.
  """
  def to_jwt(%__MODULE__{} = token) do
    current_time = System.system_time(:second)
    exp_time = current_time + (token.ttl || 3600)

    video_grant =
      token.grants
      |> Map.from_struct()
      |> Enum.map(fn {k, v} -> {Inflex.camelize(to_string(k), :lower), v} end)
      |> Enum.into(%{})

    claims = %{
      "iss" => token.api_key,
      "sub" => token.identity,
      "nbf" => current_time,
      "exp" => exp_time,
      "video" => video_grant,
      "metadata" => token.metadata,
      "name" => token.name || token.identity
    }

    signer = Joken.Signer.create("HS256", token.api_secret)
    {:ok, jwt, _claims} = Joken.encode_and_sign(claims, signer)
    jwt
  end

  @doc """
  Verifies a JWT token and returns its claims.

  ## Parameters

  - `token`: The JWT token to verify
  - `api_key`: The API key to verify against
  - `api_secret`: The API secret to verify with

  ## Returns

  - `{:ok, claims}`: If the token is valid, returns the decoded claims
  - `{:error, reason}`: If the token is invalid
  """
  @spec verify(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, any()}
  def verify(token, api_key, api_secret)
      when is_binary(token) and is_binary(api_key) and is_binary(api_secret) do
    signer = Joken.Signer.create("HS256", api_secret)

    case Joken.verify(token, signer) do
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
end

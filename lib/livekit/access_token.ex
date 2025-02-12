defmodule LiveKit.AccessToken do
  @moduledoc """
  Handles generation and management of LiveKit access tokens.
  """

  alias LiveKit.Grants

  defstruct api_key: nil,
            api_secret: nil,
            grants: %Grants{},
            identity: nil,
            ttl: nil,
            metadata: nil

  @type t :: %__MODULE__{
          api_key: String.t() | nil,
          api_secret: String.t() | nil,
          grants: Grants.t(),
          identity: String.t() | nil,
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
      "name" => token.identity
    }

    signer = Joken.Signer.create("HS256", token.api_secret)
    {:ok, jwt, _claims} = Joken.encode_and_sign(claims, signer)
    jwt
  end
end

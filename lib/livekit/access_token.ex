defmodule Livekit.AccessToken do
  @moduledoc """
  Handles generation and management of Livekit access tokens.
  """

  alias Livekit.AccessToken.VideoGrants

  @default_ttl 3600
  @participant_kinds [:standard, :egress, :ingress, :sip, :agent]

  @type kind :: :standard | :egress | :ingress | :sip | :agent

  defstruct api_key: nil,
            api_secret: nil,
            grants: %VideoGrants{},
            identity: nil,
            name: nil,
            ttl: @default_ttl,
            metadata: nil,
            kind: nil

  @type t :: %__MODULE__{
          api_key: String.t() | nil,
          api_secret: String.t() | nil,
          grants: VideoGrants.t(),
          identity: String.t() | nil,
          name: String.t() | nil,
          ttl: integer() | nil,
          metadata: String.t() | nil,
          kind: nil | kind()
        }

  @doc """
  Creates a new AccessToken with the given API key and secret.
  """
  @spec new(api_key :: String.t(), api_secret :: String.t()) :: t()
  def new(api_key, api_secret) do
    %__MODULE__{
      api_key: api_key,
      api_secret: api_secret
    }
  end

  @doc """
  Sets the identity for the token.
  """
  @spec with_identity(t(), identity :: String.t()) :: t()
  def with_identity(%__MODULE__{} = token, identity) do
    %{token | identity: identity}
  end

  @doc """
  Sets the TTL (time to live) for the token in seconds.
  """
  @spec with_ttl(t(), ttl :: integer()) :: t()
  def with_ttl(%__MODULE__{} = token, ttl) when is_integer(ttl) do
    %{token | ttl: ttl}
  end

  @doc """
  Sets metadata for the token.
  """
  @spec with_metadata(t(), String.t()) :: t()
  def with_metadata(%__MODULE__{} = token, metadata) do
    %{token | metadata: metadata}
  end

  @doc """
  Sets the name for the token.
  """
  @spec with_name(t(), String.t()) :: t()
  def with_name(%__MODULE__{} = token, name) do
    %{token | name: name}
  end

  @doc """
  Sets the grants for the token.
  """
  @spec with_grants(t(), VideoGrants.t()) :: t()
  def with_grants(%__MODULE__{} = token, %VideoGrants{} = grants) do
    %{token | grants: grants}
  end

  @doc """
  Adds a grant to the token.
  """
  @spec add_grant(t(), VideoGrants.t() | map()) :: t()
  def add_grant(%__MODULE__{} = token, grant) do
    %{token | grants: Map.merge(token.grants, grant)}
  end

  @doc """
  Sets the kind for the token.
  """
  @spec with_kind(t(), kind()) :: t()
  def with_kind(%__MODULE__{} = token, kind) when kind in @participant_kinds do
    %{token | kind: kind}
  end

  @doc """
  Generates a JWT token string.
  """
  @spec to_jwt(t()) :: jwt_token :: String.t()
  def to_jwt(%__MODULE__{} = token) do
    current_time = System.system_time(:second)
    grants = token.grants
    signer = Joken.Signer.create("HS256", token.api_secret)

    if not is_nil(grants) and
         not is_nil(grants.room_join) and
         (is_nil(token.identity) or is_nil(grants.room)) do
      raise "identity and room must be set when joining a room"
    end

    video_grants =
      grants
      |> Map.from_struct()
      |> Stream.map(fn {k, v} -> {Inflex.camelize(to_string(k), :lower), v} end)
      |> Map.new()

    claims = %{
      "iss" => token.api_key,
      "sub" => token.identity,
      "nbf" => current_time,
      "exp" => current_time + token.ttl,
      "video" => video_grants,
      "metadata" => token.metadata,
      "kind" => token.kind,
      "name" => token.name || token.identity
    }

    # in order to produce minimal JWT size, exclude None or empty values
    {:ok, jwt, _claims} =
      claims
      |> minimize_claims()
      |> Joken.encode_and_sign(signer)

    jwt
  end

  @spec minimize_claims(claims :: map()) :: map()
  defp minimize_claims(claims) do
    claims
    |> Stream.reject(fn {_k, v} -> v in [nil, ""] end)
    |> Stream.map(fn {k, v} -> if is_map(v), do: {k, minimize_claims(v)}, else: {k, v} end)
    |> Map.new()
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
  @spec verify(jwt_token :: String.t(), api_key :: String.t(), api_secret :: String.t()) ::
          {:ok, map()} | {:error, Joken.error_reason()}
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

defmodule Livekit.AccessToken do
  @moduledoc """
  Handles generation and management of Livekit access tokens.
  """

  alias Livekit.AccessToken.{InferenceGrants, SIPGrants, VideoGrants}

  @default_ttl 3600
  @participant_kinds [:standard, :egress, :ingress, :sip, :agent]

  @type api_key :: String.t()
  @type api_secret :: String.t()
  @type attributes :: %{String.t() => String.t()}
  @type claims :: map()
  @type jwt_token :: String.t()
  @type kind :: :standard | :egress | :ingress | :sip | :agent
  @type identity :: String.t()
  @type ttl :: integer()

  defstruct api_key: nil,
            api_secret: nil,
            attributes: nil,
            grants: nil,
            identity: nil,
            inference: nil,
            kind: nil,
            metadata: nil,
            name: nil,
            room_preset: nil,
            sha256: nil,
            sip: nil,
            ttl: @default_ttl

  @type t :: %__MODULE__{
          api_key: String.t() | nil,
          api_secret: String.t() | nil,
          attributes: attributes() | nil,
          grants: VideoGrants.t() | nil,
          identity: String.t() | nil,
          inference: InferenceGrants.t() | nil,
          kind: kind() | nil,
          metadata: String.t() | nil,
          name: String.t() | nil,
          room_preset: String.t() | nil,
          sha256: String.t() | nil,
          sip: SIPGrants.t() | nil,
          ttl: integer() | nil
        }

  @doc """
  Creates a new AccessToken with the given API key and secret.
  """
  @spec new(api_key(), api_secret()) :: t()
  def new(api_key, api_secret) do
    %__MODULE__{
      api_key: api_key,
      api_secret: api_secret
    }
  end

  @doc """
  Sets the identity for the token.
  """
  @spec with_identity(t(), identity()) :: t()
  def with_identity(%__MODULE__{} = token, identity) when is_binary(identity) do
    %{token | identity: identity}
  end

  @doc """
  Sets the TTL (time to live) for the token in seconds.
  """
  @spec with_ttl(t(), ttl()) :: t()
  def with_ttl(%__MODULE__{} = token, ttl) when is_integer(ttl) do
    %{token | ttl: ttl}
  end

  @doc """
  Sets metadata for the token.
  """
  @spec with_metadata(t(), String.t()) :: t()
  def with_metadata(%__MODULE__{} = token, metadata) when is_binary(metadata) do
    %{token | metadata: metadata}
  end

  @doc """
  Sets the name for the token.
  """
  @spec with_name(t(), String.t()) :: t()
  def with_name(%__MODULE__{} = token, name) when is_binary(name) do
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
  def add_grant(%__MODULE__{grants: nil} = token, grant) do
    add_grant(with_grants(token, %VideoGrants{}), grant)
  end

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
  Sets the SIP grants for the token.
  """
  @spec with_sip_grants(t(), SIPGrants.t()) :: t()
  def with_sip_grants(%__MODULE__{} = token, %SIPGrants{} = grants) do
    %{token | sip: grants}
  end

  @doc """
  Sets the inference grants for the token.
  """
  @spec with_inference_grants(t(), InferenceGrants.t()) :: t()
  def with_inference_grants(%__MODULE__{} = token, %InferenceGrants{} = grants) do
    %{token | inference: grants}
  end

  @doc """
  Sets the attributes for the token.
  """
  @spec with_attributes(t(), attributes()) :: t()
  def with_attributes(%__MODULE__{} = token, attributes) when is_map(attributes) do
    %{token | attributes: attributes}
  end

  @doc """
  Sets the SHA256 for the token.
  """
  @spec with_sha256(t(), String.t()) :: t()
  def with_sha256(%__MODULE__{} = token, sha256) when is_binary(sha256) do
    %{token | sha256: sha256}
  end

  @doc """
  Sets the room preset for the token.
  """
  @spec with_room_preset(t(), String.t()) :: t()
  def with_room_preset(%__MODULE__{} = token, room_preset) when is_binary(room_preset) do
    %{token | room_preset: room_preset}
  end

  @doc """
  Generates a JWT token string.
  """
  @spec to_jwt(t()) :: jwt_token()
  def to_jwt(%__MODULE__{} = token) do
    current_time = System.system_time(:second)
    grants = Map.get(token, :grants)
    signer = Joken.Signer.create("HS256", token.api_secret)

    if is_map(grants) and Map.get(grants, :room_join) == true and
         (token.identity in [nil, ""] or Map.get(grants, :room) in [nil, ""]) do
      raise "identity and room must be set when joining a room"
    end

    claims = %{
      "iss" => token.api_key,
      "sub" => token.identity,
      "nbf" => current_time,
      "exp" => current_time + token.ttl,
      "video" => grants,
      "metadata" => token.metadata,
      "kind" => token.kind,
      "name" => token.name || token.identity,
      "sip" => token.sip,
      "inference" => token.inference,
      "attributes" => token.attributes,
      "sha256" => token.sha256,
      "room_preset" => token.room_preset
    }

    {:ok, jwt, _claims} =
      claims
      |> claims_to_lower_camel()
      |> minimize_claims()
      |> Joken.encode_and_sign(signer)

    jwt
  end

  @spec claims_to_lower_camel(claims()) :: claims()
  defp claims_to_lower_camel(claims) when is_struct(claims) do
    claims_to_lower_camel(Map.from_struct(claims))
  end

  defp claims_to_lower_camel(claims) do
    Map.new(claims, fn {k, v} ->
      if is_map(v) do
        {snake_to_lower_camel(k), claims_to_lower_camel(v)}
      else
        {snake_to_lower_camel(k), v}
      end
    end)
  end

  # in order to produce minimal JWT size, exclude None or empty values
  @spec minimize_claims(claims()) :: claims()
  defp minimize_claims(claims) do
    claims
    |> Stream.reject(fn {_k, v} -> v in [nil, ""] end)
    |> Stream.map(fn {k, v} -> if is_map(v), do: {k, minimize_claims(v)}, else: {k, v} end)
    |> Map.new()
  end

  defp snake_to_lower_camel(value), do: Inflex.camelize(to_string(value), :lower)
end

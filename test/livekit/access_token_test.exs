defmodule Livekit.AccessTokenTest do
  use ExUnit.Case
  alias Livekit.AccessToken
  alias Livekit.Grants

  @api_key "api_key_123"
  @api_secret "secret_456"

  describe "new/2" do
    test "creates a new access token with api key and secret" do
      token = AccessToken.new(@api_key, @api_secret)
      assert token.api_key == @api_key
      assert token.api_secret == @api_secret
    end
  end

  describe "with_identity/2" do
    test "sets the identity" do
      token = AccessToken.new(@api_key, @api_secret)
      token = AccessToken.with_identity(token, "user123")
      assert token.identity == "user123"
    end
  end

  describe "with_ttl/2" do
    test "sets the TTL" do
      token = AccessToken.new(@api_key, @api_secret)
      token = AccessToken.with_ttl(token, 3600)
      assert token.ttl == 3600
    end
  end

  describe "with_metadata/2" do
    test "sets the metadata" do
      token = AccessToken.new(@api_key, @api_secret)
      token = AccessToken.with_metadata(token, "metadata123")
      assert token.metadata == "metadata123"
    end
  end

  describe "add_grant/2" do
    test "adds a grant" do
      token = AccessToken.new(@api_key, @api_secret)
      grant = Grants.join_room("room123")
      token = AccessToken.add_grant(token, grant)
      assert token.grants.room == "room123"
      assert token.grants.room_join == true
    end
  end

  describe "to_jwt/1" do
    test "generates a valid JWT token" do
      token =
        AccessToken.new(@api_key, @api_secret)
        |> AccessToken.with_identity("user123")
        |> AccessToken.with_ttl(3600)
        |> AccessToken.add_grant(Grants.join_room("room123"))

      jwt = AccessToken.to_jwt(token)
      assert is_binary(jwt)

      # Verify the token can be decoded
      {:ok, claims} = Livekit.TokenVerifier.verify(jwt, @api_secret)
      assert claims["sub"] == "user123"
      assert claims["iss"] == @api_key
      assert claims["video"]["room"] == "room123"
      assert claims["video"]["roomJoin"] == true
    end
  end
end

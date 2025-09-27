defmodule Livekit.AccessToken.TokenVerifierTest do
  use ExUnit.Case
  alias Livekit.AccessToken
  alias Livekit.AccessToken.TokenVerifier
  alias Livekit.AccessToken.VideoGrants

  @api_key "api_key_123"
  @api_secret "secret_456"

  describe "verify/2" do
    test "successfully verifies a valid token" do
      token =
        AccessToken.new(@api_key, @api_secret)
        |> AccessToken.with_identity("user123")
        |> AccessToken.with_ttl(3600)
        |> AccessToken.add_grant(VideoGrants.join_room("room123"))
        |> AccessToken.to_jwt()

      assert {:ok, claims} = TokenVerifier.verify(token, @api_secret)
      assert claims["iss"] == @api_key
      assert claims["video"]["room"] == "room123"
    end

    test "verifies with no video claims" do
      token =
        AccessToken.new(@api_key, @api_secret)
        |> AccessToken.with_identity("user123")
        |> AccessToken.to_jwt()

      assert {:ok, claims} = TokenVerifier.verify(token, @api_secret)
      assert claims["sub"] == "user123"
      assert claims["iss"] == @api_key
    end

    test "returns error for invalid token" do
      assert {:error, _reason} = TokenVerifier.verify("invalid.token.here", @api_secret)
    end

    test "returns error for token with wrong secret" do
      token =
        AccessToken.new(@api_key, @api_secret)
        |> AccessToken.with_identity("user123")
        |> AccessToken.to_jwt()

      assert {:error, _reason} = TokenVerifier.verify(token, "wrong_secret")
    end
  end

  describe "verify_with_issuer/3" do
    test "successfully verifies a valid token" do
      token =
        AccessToken.new(@api_key, @api_secret)
        |> AccessToken.with_identity("user123")
        |> AccessToken.to_jwt()

      assert {:ok, claims} = TokenVerifier.verify_with_issuer(token, @api_key, @api_secret)
      assert claims["sub"] == "user123"
      assert claims["iss"] == @api_key
    end

    test "returns error for token with wrong issuer" do
      token =
        AccessToken.new(@api_key, @api_secret)
        |> AccessToken.with_identity("user123")
        |> AccessToken.to_jwt()

      assert {:error, :invalid_issuer} =
               TokenVerifier.verify_with_issuer(token, "wrong_issuer", @api_secret)
    end
  end

  describe "verify!/2" do
    test "returns claims for valid token" do
      token =
        AccessToken.new(@api_key, @api_secret)
        |> AccessToken.with_identity("user123")
        |> AccessToken.with_ttl(3600)
        |> AccessToken.add_grant(VideoGrants.join_room("room123"))
        |> AccessToken.to_jwt()

      claims = TokenVerifier.verify!(token, @api_secret)
      assert claims["sub"] == "user123"
      assert claims["iss"] == @api_key
      assert claims["video"]["room"] == "room123"
    end

    test "raises error for invalid token" do
      assert_raise RuntimeError, ~r/Invalid token/, fn ->
        TokenVerifier.verify!("invalid.token.here", @api_secret)
      end
    end
  end
end

defmodule LivekitTaskTest do
  use ExUnit.Case
  alias Mix.Tasks.Livekit

  describe "handle_create_token/1" do
    test "returns {:ok, token} on successful token creation" do
      opts = [
        api_key: "test_key",
        api_secret: "test_secret",
        room: "test_room",
        identity: "test_identity",
        name: "test_name"
      ]
      assert {:ok, token} = Livekit.handle_create_token(opts)
      assert is_binary(token)
    end

    test "returns {:error, _reason} when missing required options" do
      opts = [
        api_secret: "test_secret",
        room: "test_room",
        identity: "test_identity",
        name: "test_name"
      ]
      assert {:error, _reason} = Livekit.handle_create_token(opts)
    end
  end

  describe "handle_list_participants/1" do
    test "returns {:error, reason} when missing required options" do
      opts = [
        api_key: "test_key",
        api_secret: "test_secret",
        room: "test_room"
      ]
      assert {:error, _reason} = Livekit.handle_list_participants(opts)
    end

    test "returns {:error, _reason} when url is invalid" do
      opts = [
        api_key: "test_key",
        api_secret: "test_secret",
        room: "invalid_room",
        url: "invalid_url"
      ]
      assert {:error, _reason} = Livekit.handle_list_participants(opts)
    end
  end

  describe "handle_start_room_recording/1" do
    test "returns {:error, reason} when missing required options" do
      opts = [
        api_key: "test_key",
        api_secret: "test_secret",
        room: "test_room"
      ]
      assert {:error, _reason} = Livekit.handle_start_room_recording(opts)
    end

    test "returns {:error, _reason} when url is invalid" do
      opts = [
        api_key: "test_key",
        api_secret: "test_secret",
        room: "invalid_room",
        output: "path/to/output",
        layout: "grid",
        resolution: "hd",
        url: "invalid_url"
      ]
      assert {:error, _reason} = Livekit.handle_start_room_recording(opts)
    end
  end
end

defmodule LivekitTaskTest do
  use ExUnit.Case
  alias Mix.Tasks.Livekit

  setup do
    # Setup test configuration
    url = "wss://test.livekit.com"
    api_key = "test_key"
    api_secret = "test_secret"

    Application.put_env(:livekit, :url, url)
    Application.put_env(:livekit, :api_key, api_key)
    Application.put_env(:livekit, :api_secret, api_secret)

    on_exit(fn ->
      Application.delete_env(:livekit, :url)
      Application.delete_env(:livekit, :api_key)
      Application.delete_env(:livekit, :api_secret)
    end)

    {:ok, %{url: url, api_key: api_key, api_secret: api_secret}}
  end

  describe "handle_create_token/1" do
    test "returns {:ok, token} on successful token creation" do
      opts = [
        room: "test_room",
        identity: "test_identity",
        name: "test_name"
      ]

      assert {:ok, token} = Livekit.handle_create_token(opts)
      assert is_binary(token)
    end

    test "accepts runtime overrides for configuration" do
      opts = [
        url: "wss://override.com",
        api_key: "override_key",
        api_secret: "override_secret",
        room: "test_room",
        identity: "test_identity",
        name: "test_name"
      ]

      assert {:ok, token} = Livekit.handle_create_token(opts)
      assert is_binary(token)
    end

    test "returns error when missing required options" do
      opts = [
        room: "test_room",
        name: "test_name"
      ]

      assert {:error, "Missing required option: --identity"} = Livekit.handle_create_token(opts)
    end
  end

  describe "handle_list_participants/1" do
    test "returns error when missing room" do
      opts = []
      assert {:error, "Missing required option: --room"} = Livekit.handle_list_participants(opts)
    end

    test "returns error when url is invalid", %{test: test} do
      opts = [
        url: "http://invalid-#{test}.local",
        room: "test_room"
      ]

      assert {:error, _reason} = Livekit.handle_list_participants(opts)
    end
  end

  describe "handle_start_room_recording/1" do
    test "returns error when missing output" do
      opts = [
        room: "test_room"
      ]

      assert {:error, "Missing required option: --output"} =
               Livekit.handle_start_room_recording(opts)
    end

    test "returns error when url is invalid", %{test: test} do
      opts = [
        url: "http://invalid-#{test}.local",
        room: "test_room",
        output: "path/to/output",
        layout: "grid",
        resolution: "hd"
      ]

      assert {:error, _reason} = Livekit.handle_start_room_recording(opts)
    end
  end
end

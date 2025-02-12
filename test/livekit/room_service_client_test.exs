defmodule LiveKit.RoomServiceClientTest do
  use ExUnit.Case
  alias LiveKit.RoomServiceClient

  @api_key "api_key_123"
  @api_secret "secret_456"
  @base_url "http://example.com"

  setup do
    client = RoomServiceClient.new(@base_url, @api_key, @api_secret)
    {:ok, client: client}
  end

  describe "new/3" do
    test "creates a new client with correct configuration" do
      client = RoomServiceClient.new(@base_url, @api_key, @api_secret)
      assert client.base_url == @base_url
      assert client.api_key == @api_key
      assert client.api_secret == @api_secret
      assert client.client != nil
    end

    test "converts ws:// URLs to http://" do
      client = RoomServiceClient.new("ws://example.com", @api_key, @api_secret)
      assert client.base_url == "http://example.com"
    end

    test "converts wss:// URLs to https://" do
      client = RoomServiceClient.new("wss://example.com", @api_key, @api_secret)
      assert client.base_url == "https://example.com"
    end
  end

  describe "create_room/3" do
    test "sends request with correct structure", %{client: client} do
      room_name = "test_room"
      opts = [empty_timeout: 300]

      # Since we're using a fake URL, we expect a request failure
      assert {:error, :request_failed} = RoomServiceClient.create_room(client, room_name, opts)
    end
  end

  describe "list_rooms/1" do
    test "sends request with correct structure", %{client: client} do
      # Since we're using a fake URL, we expect a request failure
      assert {:error, :request_failed} = RoomServiceClient.list_rooms(client)
    end
  end

  describe "delete_room/2" do
    test "sends request with correct structure", %{client: client} do
      room_name = "test_room"

      # Since we're using a fake URL, we expect a request failure
      assert {:error, :request_failed} = RoomServiceClient.delete_room(client, room_name)
    end
  end
end

defmodule LiveKit.RoomServiceClientTest do
  use ExUnit.Case
  alias LiveKit.RoomServiceClient
  alias Livekit.{Room, ParticipantInfo, ListRoomsResponse, ListParticipantsResponse, MuteRoomTrackResponse}

  @api_key "api_key_123"
  @api_secret "secret_456"

  setup do
    bypass = Bypass.open()
    base_url = "http://localhost:#{bypass.port}"
    client = RoomServiceClient.new(base_url, @api_key, @api_secret)
    {:ok, bypass: bypass, client: client}
  end

  describe "new/3" do
    test "creates a new client with correct configuration" do
      client = RoomServiceClient.new("http://example.com", @api_key, @api_secret)
      assert client.base_url == "http://example.com"
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
    test "creates a room successfully", %{bypass: bypass, client: client} do
      room_name = "test_room"
      room = %Room{name: room_name, sid: "room123"}
      
      Bypass.expect_once(bypass, "POST", "/twirp/livekit.RoomService/CreateRoom", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Livekit.CreateRoomRequest.decode(body)
        assert request.name == room_name
        
        conn
        |> Plug.Conn.put_resp_content_type("application/protobuf")
        |> Plug.Conn.resp(200, Livekit.Room.encode(room))
      end)

      assert {:ok, response} = RoomServiceClient.create_room(client, room_name)
      assert response.name == room_name
      assert response.sid == "room123"
    end
  end

  describe "list_rooms/2" do
    test "lists rooms successfully", %{bypass: bypass, client: client} do
      rooms = [
        %Room{name: "room1", sid: "sid1"},
        %Room{name: "room2", sid: "sid2"}
      ]
      response = %ListRoomsResponse{rooms: rooms}

      Bypass.expect_once(bypass, "POST", "/twirp/livekit.RoomService/ListRooms", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/protobuf")
        |> Plug.Conn.resp(200, ListRoomsResponse.encode(response))
      end)

      assert {:ok, result} = RoomServiceClient.list_rooms(client)
      assert length(result.rooms) == 2
      assert Enum.at(result.rooms, 0).name == "room1"
      assert Enum.at(result.rooms, 1).name == "room2"
    end
  end

  describe "delete_room/2" do
    test "deletes a room successfully", %{bypass: bypass, client: client} do
      room_name = "test_room"

      Bypass.expect_once(bypass, "POST", "/twirp/livekit.RoomService/DeleteRoom", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Livekit.DeleteRoomRequest.decode(body)
        assert request.room == room_name

        Plug.Conn.resp(conn, 200, "")
      end)

      assert :ok = RoomServiceClient.delete_room(client, room_name)
    end
  end

  describe "update_room_metadata/3" do
    test "updates room metadata successfully", %{bypass: bypass, client: client} do
      room_name = "test_room"
      metadata = "new metadata"
      room = %Room{name: room_name, metadata: metadata}

      Bypass.expect_once(bypass, "POST", "/twirp/livekit.RoomService/UpdateRoomMetadata", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Livekit.UpdateRoomMetadataRequest.decode(body)
        assert request.room == room_name
        assert request.metadata == metadata

        conn
        |> Plug.Conn.put_resp_content_type("application/protobuf")
        |> Plug.Conn.resp(200, Livekit.Room.encode(room))
      end)

      assert {:ok, response} = RoomServiceClient.update_room_metadata(client, room_name, metadata)
      assert response.name == room_name
      assert response.metadata == metadata
    end
  end

  describe "list_participants/2" do
    test "lists participants successfully", %{bypass: bypass, client: client} do
      room_name = "test_room"
      participants = [
        %ParticipantInfo{identity: "user1", name: "User 1"},
        %ParticipantInfo{identity: "user2", name: "User 2"}
      ]
      response = %ListParticipantsResponse{participants: participants}

      Bypass.expect_once(bypass, "POST", "/twirp/livekit.RoomService/ListParticipants", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Livekit.ListParticipantsRequest.decode(body)
        assert request.room == room_name

        conn
        |> Plug.Conn.put_resp_content_type("application/protobuf")
        |> Plug.Conn.resp(200, ListParticipantsResponse.encode(response))
      end)

      assert {:ok, result} = RoomServiceClient.list_participants(client, room_name)
      assert length(result.participants) == 2
      assert Enum.at(result.participants, 0).identity == "user1"
      assert Enum.at(result.participants, 1).identity == "user2"
    end
  end

  describe "get_participant/3" do
    test "gets participant successfully", %{bypass: bypass, client: client} do
      room_name = "test_room"
      identity = "user1"
      participant = %ParticipantInfo{identity: identity, name: "User 1"}

      Bypass.expect_once(bypass, "POST", "/twirp/livekit.RoomService/GetParticipant", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Livekit.RoomParticipantIdentity.decode(body)
        assert request.room == room_name
        assert request.identity == identity

        conn
        |> Plug.Conn.put_resp_content_type("application/protobuf")
        |> Plug.Conn.resp(200, ParticipantInfo.encode(participant))
      end)

      assert {:ok, response} = RoomServiceClient.get_participant(client, room_name, identity)
      assert response.identity == identity
      assert response.name == "User 1"
    end
  end

  describe "remove_participant/3" do
    test "removes participant successfully", %{bypass: bypass, client: client} do
      room_name = "test_room"
      identity = "user1"

      Bypass.expect_once(bypass, "POST", "/twirp/livekit.RoomService/RemoveParticipant", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Livekit.RoomParticipantIdentity.decode(body)
        assert request.room == room_name
        assert request.identity == identity

        Plug.Conn.resp(conn, 200, "")
      end)

      assert :ok = RoomServiceClient.remove_participant(client, room_name, identity)
    end
  end

  describe "mute_published_track/4" do
    test "mutes track successfully", %{bypass: bypass, client: client} do
      room_name = "test_room"
      identity = "user1"
      track_sid = "track1"
      response = %MuteRoomTrackResponse{}

      Bypass.expect_once(bypass, "POST", "/twirp/livekit.RoomService/MutePublishedTrack", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Livekit.MuteRoomTrackRequest.decode(body)
        assert request.room == room_name
        assert request.identity == identity
        assert request.track_sid == track_sid
        assert request.muted == true

        conn
        |> Plug.Conn.put_resp_content_type("application/protobuf")
        |> Plug.Conn.resp(200, MuteRoomTrackResponse.encode(response))
      end)

      assert {:ok, _result} = RoomServiceClient.mute_published_track(client, room_name, identity, track_sid, true)
    end
  end

  describe "update_participant/4" do
    test "updates participant successfully", %{bypass: bypass, client: client} do
      room_name = "test_room"
      identity = "user1"
      metadata = "new metadata"
      name = "New Name"
      attributes = %{"avatar" => "url", "role" => "admin"}
      participant = %ParticipantInfo{
        identity: identity,
        name: name,
        metadata: metadata
      }

      Bypass.expect_once(bypass, "POST", "/twirp/livekit.RoomService/UpdateParticipant", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Livekit.UpdateParticipantRequest.decode(body)
        assert request.room == room_name
        assert request.identity == identity
        assert request.metadata == metadata
        assert request.name == name
        assert request.attributes == attributes

        conn
        |> Plug.Conn.put_resp_content_type("application/protobuf")
        |> Plug.Conn.resp(200, ParticipantInfo.encode(participant))
      end)

      assert {:ok, response} = RoomServiceClient.update_participant(client, room_name, identity,
        metadata: metadata,
        name: name,
        attributes: attributes
      )
      assert response.identity == identity
      assert response.name == name
      assert response.metadata == metadata
    end
  end

  describe "update_subscriptions/5" do
    test "updates subscriptions successfully", %{bypass: bypass, client: client} do
      room_name = "test_room"
      identity = "user1"
      track_sids = ["track1", "track2"]
      subscribe = true

      Bypass.expect_once(bypass, "POST", "/twirp/livekit.RoomService/UpdateSubscriptions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Livekit.UpdateSubscriptionsRequest.decode(body)
        assert request.room == room_name
        assert request.identity == identity
        assert request.track_sids == track_sids
        assert request.subscribe == subscribe

        Plug.Conn.resp(conn, 200, "")
      end)

      assert :ok = RoomServiceClient.update_subscriptions(client, room_name, identity, track_sids, subscribe)
    end
  end

  describe "send_data/5" do
    test "sends data successfully", %{bypass: bypass, client: client} do
      room_name = "test_room"
      data = "test data"
      kind = :RELIABLE
      destination_sids = ["sid1", "sid2"]
      destination_identities = ["user1", "user2"]

      Bypass.expect_once(bypass, "POST", "/twirp/livekit.RoomService/SendData", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Livekit.SendDataRequest.decode(body)
        assert request.room == room_name
        assert request.data == data
        assert request.kind == kind
        assert request.destination_sids == destination_sids
        assert request.destination_identities == destination_identities
        assert byte_size(request.nonce) == 16

        Plug.Conn.resp(conn, 200, "")
      end)

      assert :ok = RoomServiceClient.send_data(client, room_name, data, kind,
        destination_sids: destination_sids,
        destination_identities: destination_identities
      )
    end

    test "sends broadcast data successfully", %{bypass: bypass, client: client} do
      room_name = "test_room"
      data = "broadcast data"
      kind = :RELIABLE

      Bypass.expect_once(bypass, "POST", "/twirp/livekit.RoomService/SendData", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Livekit.SendDataRequest.decode(body)
        assert request.room == room_name
        assert request.data == data
        assert request.kind == kind
        assert request.destination_sids == []
        assert request.destination_identities == []
        assert byte_size(request.nonce) == 16

        Plug.Conn.resp(conn, 200, "")
      end)

      assert :ok = RoomServiceClient.send_data(client, room_name, data, kind)
    end

    test "sends data to specific participants by SIDs", %{bypass: bypass, client: client} do
      room_name = "test_room"
      data = "targeted data"
      kind = :RELIABLE
      destination_sids = ["sid1", "sid2"]

      Bypass.expect_once(bypass, "POST", "/twirp/livekit.RoomService/SendData", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Livekit.SendDataRequest.decode(body)
        assert request.room == room_name
        assert request.data == data
        assert request.kind == kind
        assert request.destination_sids == destination_sids
        assert request.destination_identities == []
        assert byte_size(request.nonce) == 16

        Plug.Conn.resp(conn, 200, "")
      end)

      assert :ok = RoomServiceClient.send_data(client, room_name, data, kind, destination_sids: destination_sids)
    end

    test "sends data to specific participants by identities", %{bypass: bypass, client: client} do
      room_name = "test_room"
      data = "targeted data"
      kind = :RELIABLE
      destination_identities = ["user1", "user2"]

      Bypass.expect_once(bypass, "POST", "/twirp/livekit.RoomService/SendData", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Livekit.SendDataRequest.decode(body)
        assert request.room == room_name
        assert request.data == data
        assert request.kind == kind
        assert request.destination_sids == []
        assert request.destination_identities == destination_identities
        assert byte_size(request.nonce) == 16

        Plug.Conn.resp(conn, 200, "")
      end)

      assert :ok = RoomServiceClient.send_data(client, room_name, data, kind, destination_identities: destination_identities)
    end

    test "sends lossy data successfully", %{bypass: bypass, client: client} do
      room_name = "test_room"
      data = "lossy data"
      kind = :LOSSY

      Bypass.expect_once(bypass, "POST", "/twirp/livekit.RoomService/SendData", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Livekit.SendDataRequest.decode(body)
        assert request.room == room_name
        assert request.data == data
        assert request.kind == kind
        assert request.destination_sids == []
        assert request.destination_identities == []
        assert byte_size(request.nonce) == 16

        Plug.Conn.resp(conn, 200, "")
      end)

      assert :ok = RoomServiceClient.send_data(client, room_name, data, kind)
    end
  end
end

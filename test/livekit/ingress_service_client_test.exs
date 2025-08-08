defmodule Livekit.IngressServiceClientTest do
  use ExUnit.Case
  import Mock

  alias Livekit.IngressServiceClient

  alias Livekit.{
    CreateIngressRequest,
    DeleteIngressRequest,
    IngressInfo,
    IngressState,
    ListIngressRequest,
    ListIngressResponse,
    UpdateIngressRequest
  }

  @api_key "api_key_123"
  @api_secret "secret_456"
  @url "wss://example.com"

  describe "new/3" do
    test "creates a new client successfully with https URL" do
      with_mock GRPC.Stub, connect: fn _host, _opts -> {:ok, :channel} end do
        assert {:ok, {channel, metadata}} = IngressServiceClient.new(@url, @api_key, @api_secret)
        assert channel == :channel
        assert Map.has_key?(metadata, "authorization")
        assert String.starts_with?(metadata["authorization"], "Bearer ")
      end
    end

    test "converts ws:// URL to http://" do
      with_mock GRPC.Stub,
        connect: fn host, _opts ->
          assert String.contains?(host, "example.com:80")
          {:ok, :channel}
        end do
        IngressServiceClient.new("ws://example.com", @api_key, @api_secret)
      end
    end

    test "converts wss:// URL to https://" do
      with_mock GRPC.Stub,
        connect: fn host, opts ->
          assert String.contains?(host, "example.com:443")
          assert Keyword.get(opts, :cred) != nil
          {:ok, :channel}
        end do
        IngressServiceClient.new("wss://example.com", @api_key, @api_secret)
      end
    end

    test "returns error when connection fails" do
      with_mock GRPC.Stub, connect: fn _host, _opts -> {:error, :connection_failed} end do
        assert {:error, error_msg} = IngressServiceClient.new(@url, @api_key, @api_secret)
        assert String.contains?(error_msg, "Failed to connect")
      end
    end

    test "validates required parameters" do
      # The function guards require is_binary, so non-binary types should fail
      assert_raise FunctionClauseError, fn ->
        IngressServiceClient.new(nil, @api_key, @api_secret)
      end

      assert_raise FunctionClauseError, fn ->
        IngressServiceClient.new(@url, nil, @api_secret)
      end

      assert_raise FunctionClauseError, fn ->
        IngressServiceClient.new(@url, @api_key, nil)
      end
    end
  end

  describe "create_ingress/2" do
    setup do
      client = {:channel, %{"authorization" => "Bearer test_token"}}
      {:ok, client: client}
    end

    test "creates RTMP ingress successfully", %{client: client} do
      request = %CreateIngressRequest{
        input_type: :RTMP_INPUT,
        name: "test-stream",
        room_name: "test-room",
        participant_identity: "streamer"
      }

      expected_ingress = %IngressInfo{
        ingress_id: "ingress_123",
        name: "test-stream",
        url: "rtmp://example.com/live",
        stream_key: "stream_key_456",
        input_type: :RTMP_INPUT,
        room_name: "test-room",
        participant_identity: "streamer"
      }

      with_mock Livekit.Ingress.Stub,
        create_ingress: fn _channel, _request, _opts -> {:ok, expected_ingress} end do
        assert {:ok, ingress} = IngressServiceClient.create_ingress(client, request)
        assert ingress.ingress_id == "ingress_123"
        assert ingress.name == "test-stream"
        assert ingress.input_type == :RTMP_INPUT
        assert ingress.room_name == "test-room"
        assert ingress.participant_identity == "streamer"
      end
    end

    test "creates WHIP ingress with metadata", %{client: client} do
      request = %CreateIngressRequest{
        input_type: :WHIP_INPUT,
        name: "whip-test",
        room_name: "test-room",
        participant_identity: "whip-user",
        participant_metadata: "custom-metadata"
      }

      expected_ingress = %IngressInfo{
        ingress_id: "whip_123",
        name: "whip-test",
        url: "https://example.com/whip",
        input_type: :WHIP_INPUT,
        room_name: "test-room",
        participant_identity: "whip-user"
      }

      with_mock Livekit.Ingress.Stub,
        create_ingress: fn _channel, received_request, _opts ->
          assert received_request.input_type == :WHIP_INPUT
          assert received_request.participant_metadata == "custom-metadata"
          {:ok, expected_ingress}
        end do
        assert {:ok, ingress} = IngressServiceClient.create_ingress(client, request)
        assert ingress.ingress_id == "whip_123"
        assert ingress.input_type == :WHIP_INPUT
      end
    end

    test "creates URL ingress with source URL", %{client: client} do
      request = %CreateIngressRequest{
        input_type: :URL_INPUT,
        name: "url-test",
        room_name: "test-room",
        participant_identity: "url-user",
        url: "https://example.com/stream.m3u8"
      }

      expected_ingress = %IngressInfo{
        ingress_id: "url_123",
        name: "url-test",
        url: "https://example.com/stream.m3u8",
        input_type: :URL_INPUT,
        room_name: "test-room",
        participant_identity: "url-user"
      }

      with_mock Livekit.Ingress.Stub,
        create_ingress: fn _channel, received_request, _opts ->
          assert received_request.input_type == :URL_INPUT
          assert received_request.url == "https://example.com/stream.m3u8"
          {:ok, expected_ingress}
        end do
        assert {:ok, ingress} = IngressServiceClient.create_ingress(client, request)
        assert ingress.ingress_id == "url_123"
        assert ingress.input_type == :URL_INPUT
        assert ingress.url == "https://example.com/stream.m3u8"
      end
    end

    test "handles gRPC errors", %{client: client} do
      request = %CreateIngressRequest{
        input_type: :RTMP_INPUT,
        name: "test-stream",
        room_name: "test-room",
        participant_identity: "streamer"
      }

      grpc_error = %GRPC.RPCError{status: 3, message: "Invalid argument"}

      with_mock Livekit.Ingress.Stub,
        create_ingress: fn _channel, _request, _opts -> {:error, grpc_error} end do
        assert {:error, "Invalid argument"} = IngressServiceClient.create_ingress(client, request)
      end
    end

    test "handles other errors", %{client: client} do
      request = %CreateIngressRequest{
        input_type: :RTMP_INPUT,
        name: "test-stream",
        room_name: "test-room",
        participant_identity: "streamer"
      }

      with_mock Livekit.Ingress.Stub,
        create_ingress: fn _channel, _request, _opts -> {:error, :timeout} end do
        assert {:error, :timeout} = IngressServiceClient.create_ingress(client, request)
      end
    end
  end

  describe "update_ingress/2" do
    setup do
      client = {:channel, %{"authorization" => "Bearer test_token"}}
      {:ok, client: client}
    end

    test "updates ingress successfully", %{client: client} do
      request = %UpdateIngressRequest{
        ingress_id: "ingress_123",
        name: "updated-stream",
        room_name: "new-room"
      }

      expected_ingress = %IngressInfo{
        ingress_id: "ingress_123",
        name: "updated-stream",
        room_name: "new-room",
        participant_identity: "streamer"
      }

      with_mock Livekit.Ingress.Stub,
        update_ingress: fn _channel, _request, _opts -> {:ok, expected_ingress} end do
        assert {:ok, ingress} = IngressServiceClient.update_ingress(client, request)
        assert ingress.ingress_id == "ingress_123"
        assert ingress.name == "updated-stream"
        assert ingress.room_name == "new-room"
      end
    end

    test "updates multiple fields successfully", %{client: client} do
      request = %UpdateIngressRequest{
        ingress_id: "ingress_123",
        name: "updated-stream",
        room_name: "new-room",
        participant_identity: "new-identity",
        participant_metadata: "updated-metadata"
      }

      expected_ingress = %IngressInfo{
        ingress_id: "ingress_123",
        name: "updated-stream",
        room_name: "new-room",
        participant_identity: "new-identity"
      }

      with_mock Livekit.Ingress.Stub,
        update_ingress: fn _channel, received_request, _opts ->
          assert received_request.ingress_id == "ingress_123"
          assert received_request.name == "updated-stream"
          assert received_request.room_name == "new-room"
          assert received_request.participant_identity == "new-identity"
          assert received_request.participant_metadata == "updated-metadata"
          {:ok, expected_ingress}
        end do
        assert {:ok, ingress} = IngressServiceClient.update_ingress(client, request)
        assert ingress.ingress_id == "ingress_123"
        assert ingress.name == "updated-stream"
        assert ingress.room_name == "new-room"
        assert ingress.participant_identity == "new-identity"
      end
    end

    test "handles update errors", %{client: client} do
      request = %UpdateIngressRequest{
        ingress_id: "nonexistent",
        name: "updated-stream"
      }

      grpc_error = %GRPC.RPCError{status: 5, message: "Not found"}

      with_mock Livekit.Ingress.Stub,
        update_ingress: fn _channel, _request, _opts -> {:error, grpc_error} end do
        assert {:error, "Not found"} = IngressServiceClient.update_ingress(client, request)
      end
    end

    test "handles state validation errors", %{client: client} do
      request = %UpdateIngressRequest{
        ingress_id: "active_ingress",
        name: "updated-stream"
      }

      grpc_error = %GRPC.RPCError{status: 9, message: "Ingress can only be updated when inactive"}

      with_mock Livekit.Ingress.Stub,
        update_ingress: fn _channel, _request, _opts -> {:error, grpc_error} end do
        assert {:error, "Ingress can only be updated when inactive"} =
                 IngressServiceClient.update_ingress(client, request)
      end
    end
  end

  describe "list_ingress/2" do
    setup do
      client = {:channel, %{"authorization" => "Bearer test_token"}}
      {:ok, client: client}
    end

    test "lists ingress endpoints successfully", %{client: client} do
      ingress1 = %IngressInfo{
        ingress_id: "ingress_1",
        name: "stream1",
        input_type: :RTMP_INPUT,
        room_name: "room1"
      }

      ingress2 = %IngressInfo{
        ingress_id: "ingress_2",
        name: "stream2",
        input_type: :WHIP_INPUT,
        room_name: "room2"
      }

      expected_response = %ListIngressResponse{items: [ingress1, ingress2]}

      with_mock Livekit.Ingress.Stub,
        list_ingress: fn _channel, _request, _opts -> {:ok, expected_response} end do
        assert {:ok, response} = IngressServiceClient.list_ingress(client)
        assert length(response.items) == 2
        assert Enum.at(response.items, 0).ingress_id == "ingress_1"
        assert Enum.at(response.items, 1).ingress_id == "ingress_2"
      end
    end

    test "lists ingress with filters", %{client: client} do
      request = %ListIngressRequest{room_name: "test-room"}
      expected_response = %ListIngressResponse{items: []}

      with_mock Livekit.Ingress.Stub,
        list_ingress: fn _channel, req, _opts ->
          assert req.room_name == "test-room"
          {:ok, expected_response}
        end do
        assert {:ok, _response} = IngressServiceClient.list_ingress(client, request)
      end
    end

    test "handles empty list", %{client: client} do
      expected_response = %ListIngressResponse{items: []}

      with_mock Livekit.Ingress.Stub,
        list_ingress: fn _channel, _request, _opts -> {:ok, expected_response} end do
        assert {:ok, response} = IngressServiceClient.list_ingress(client)
        assert response.items == []
      end
    end
  end

  describe "delete_ingress/2" do
    setup do
      client = {:channel, %{"authorization" => "Bearer test_token"}}
      {:ok, client: client}
    end

    test "deletes ingress successfully", %{client: client} do
      request = %DeleteIngressRequest{ingress_id: "ingress_123"}

      expected_ingress = %IngressInfo{
        ingress_id: "ingress_123",
        name: "deleted-stream",
        state: %IngressState{status: :ENDPOINT_COMPLETE}
      }

      with_mock Livekit.Ingress.Stub,
        delete_ingress: fn _channel, _request, _opts -> {:ok, expected_ingress} end do
        assert {:ok, ingress} = IngressServiceClient.delete_ingress(client, request)
        assert ingress.ingress_id == "ingress_123"
        assert ingress.name == "deleted-stream"
      end
    end

    test "handles delete errors", %{client: client} do
      request = %DeleteIngressRequest{ingress_id: "nonexistent"}

      grpc_error = %GRPC.RPCError{status: 5, message: "Ingress not found"}

      with_mock Livekit.Ingress.Stub,
        delete_ingress: fn _channel, _request, _opts -> {:error, grpc_error} end do
        assert {:error, "Ingress not found"} =
                 IngressServiceClient.delete_ingress(client, request)
      end
    end
  end

  describe "error handling and edge cases" do
    test "handles malformed client tuple" do
      invalid_client = {:invalid, "data"}

      request = %CreateIngressRequest{
        input_type: :RTMP_INPUT,
        name: "test",
        room_name: "test",
        participant_identity: "test"
      }

      # The function will try to use the invalid channel and fail
      assert_raise UndefinedFunctionError, fn ->
        IngressServiceClient.create_ingress(invalid_client, request)
      end
    end

    test "validates request structs" do
      client = {:channel, %{"authorization" => "Bearer test_token"}}

      # Should fail with pattern match for wrong struct type
      assert_raise FunctionClauseError, fn ->
        IngressServiceClient.create_ingress(client, %{not: "valid"})
      end
    end

    test "logs successful operations" do
      client = {:channel, %{"authorization" => "Bearer test_token"}}

      request = %CreateIngressRequest{
        input_type: :RTMP_INPUT,
        name: "test-stream",
        room_name: "test-room",
        participant_identity: "streamer"
      }

      expected_ingress = %IngressInfo{
        ingress_id: "ingress_123",
        name: "test-stream"
      }

      with_mock Livekit.Ingress.Stub,
        create_ingress: fn _channel, _request, _opts -> {:ok, expected_ingress} end do
        import ExUnit.CaptureLog

        log =
          capture_log(fn ->
            assert {:ok, _ingress} = IngressServiceClient.create_ingress(client, request)
          end)

        assert log =~ "Created ingress: ingress_123"
      end
    end

    test "logs error operations" do
      client = {:channel, %{"authorization" => "Bearer test_token"}}

      request = %CreateIngressRequest{
        input_type: :RTMP_INPUT,
        name: "test-stream",
        room_name: "test-room",
        participant_identity: "streamer"
      }

      grpc_error = %GRPC.RPCError{status: 3, message: "Invalid argument"}

      with_mock Livekit.Ingress.Stub,
        create_ingress: fn _channel, _request, _opts -> {:error, grpc_error} end do
        import ExUnit.CaptureLog

        log =
          capture_log(fn ->
            assert {:error, _reason} = IngressServiceClient.create_ingress(client, request)
          end)

        assert log =~ "Failed to create ingress: Invalid argument"
      end
    end
  end

  describe "integration scenarios" do
    setup do
      client = {:channel, %{"authorization" => "Bearer test_token"}}
      {:ok, client: client}
    end

    test "full ingress lifecycle", %{client: client} do
      # Create
      create_request = %CreateIngressRequest{
        input_type: :RTMP_INPUT,
        name: "lifecycle-test",
        room_name: "test-room",
        participant_identity: "streamer"
      }

      created_ingress = %IngressInfo{
        ingress_id: "lifecycle_123",
        name: "lifecycle-test",
        input_type: :RTMP_INPUT,
        room_name: "test-room",
        participant_identity: "streamer",
        url: "rtmp://example.com/live",
        stream_key: "key123"
      }

      # Update
      update_request = %UpdateIngressRequest{
        ingress_id: "lifecycle_123",
        name: "updated-lifecycle-test"
      }

      updated_ingress = %{created_ingress | name: "updated-lifecycle-test"}

      # List
      list_response = %ListIngressResponse{items: [updated_ingress]}

      # Delete
      delete_request = %DeleteIngressRequest{ingress_id: "lifecycle_123"}

      with_mocks([
        {Livekit.Ingress.Stub, [],
         [
           create_ingress: fn _channel, _request, _opts -> {:ok, created_ingress} end,
           update_ingress: fn _channel, _request, _opts -> {:ok, updated_ingress} end,
           list_ingress: fn _channel, _request, _opts -> {:ok, list_response} end,
           delete_ingress: fn _channel, _request, _opts -> {:ok, updated_ingress} end
         ]}
      ]) do
        # Test full lifecycle
        assert {:ok, ingress} = IngressServiceClient.create_ingress(client, create_request)
        assert ingress.ingress_id == "lifecycle_123"

        assert {:ok, updated} = IngressServiceClient.update_ingress(client, update_request)
        assert updated.name == "updated-lifecycle-test"

        assert {:ok, list_result} = IngressServiceClient.list_ingress(client)
        assert length(list_result.items) == 1

        assert {:ok, deleted} = IngressServiceClient.delete_ingress(client, delete_request)
        assert deleted.ingress_id == "lifecycle_123"
      end
    end
  end
end

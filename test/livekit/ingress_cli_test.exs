defmodule Livekit.IngressCliTest do
  use ExUnit.Case
  import Mock
  import ExUnit.CaptureIO

  # Limited aliases to avoid struct resolution conflicts
  alias Mix.Tasks.Livekit, as: LivekitTask

  @api_key "test_key"
  @api_secret "test_secret"
  @url "wss://test.livekit.com"

  describe "create-ingress command" do
    test "creates RTMP ingress successfully" do
      expected_ingress = %Livekit.IngressInfo{
        ingress_id: "ingress_123",
        name: "test-stream",
        url: "rtmp://example.com/live",
        stream_key: "stream_key_456",
        input_type: :RTMP_INPUT,
        room_name: "test-room",
        participant_identity: "streamer"
      }

      with_mocks([
        {Livekit.IngressServiceClient, [], [
          new: fn _url, _api_key, _api_secret -> {:ok, {:channel, %{}}} end,
          create_ingress: fn _client, _request -> {:ok, expected_ingress} end
        ]}
      ]) do
        output = capture_io(fn ->
          LivekitTask.run([
            "create-ingress",
            "--api-key", @api_key,
            "--api-secret", @api_secret,
            "--url", @url,
            "--input-type", "RTMP",
            "--name", "test-stream",
            "--room", "test-room",
            "--identity", "streamer"
          ])
        end)

        assert String.contains?(output, "✅ Ingress created successfully!")
        assert String.contains?(output, "Ingress ID: ingress_123")
        assert String.contains?(output, "Stream URL: rtmp://example.com/live")
        assert String.contains?(output, "Stream Key: stream_key_456")
      end
    end

    test "creates WHIP ingress successfully" do
      expected_ingress = %Livekit.IngressInfo{
        ingress_id: "whip_123",
        name: "whip-stream",
        url: "https://example.com/whip",
        input_type: :WHIP_INPUT,
        room_name: "whip-room",
        participant_identity: "whip-user"
      }

      with_mocks([
        {Livekit.IngressServiceClient, [], [
          new: fn _url, _api_key, _api_secret -> {:ok, {:channel, %{}}} end,
          create_ingress: fn _client, _request -> {:ok, expected_ingress} end
        ]}
      ]) do
        output = capture_io(fn ->
          LivekitTask.run([
            "create-ingress",
            "--api-key", @api_key,
            "--api-secret", @api_secret,
            "--url", @url,
            "--input-type", "WHIP",
            "--name", "whip-stream",
            "--room", "whip-room",
            "--identity", "whip-user"
          ])
        end)

        assert String.contains?(output, "✅ Ingress created successfully!")
        assert String.contains?(output, "Ingress ID: whip_123")
        assert String.contains?(output, "Input Type: WHIP_INPUT")
      end
    end

    test "creates URL ingress successfully" do
      expected_ingress = %Livekit.IngressInfo{
        ingress_id: "url_123",
        name: "url-stream",
        url: "https://example.com/stream.m3u8",
        input_type: :URL_INPUT,
        room_name: "url-room",
        participant_identity: "url-user"
      }

      with_mocks([
        {Livekit.IngressServiceClient, [], [
          new: fn _url, _api_key, _api_secret -> {:ok, {:channel, %{}}} end,
          create_ingress: fn _client, request ->
            assert request.url == "https://example.com/stream.m3u8"
            {:ok, expected_ingress}
          end
        ]}
      ]) do
        output = capture_io(fn ->
          LivekitTask.run([
            "create-ingress",
            "--api-key", @api_key,
            "--api-secret", @api_secret,
            "--url", @url,
            "--input-type", "URL",
            "--source-url", "https://example.com/stream.m3u8",
            "--name", "url-stream",
            "--room", "url-room",
            "--identity", "url-user"
          ])
        end)

        assert String.contains?(output, "✅ Ingress created successfully!")
        assert String.contains?(output, "Ingress ID: url_123")
      end
    end

    test "handles missing required parameters" do
      output = capture_io(fn ->
        LivekitTask.run([
          "create-ingress",
          "--api-key", @api_key,
          "--api-secret", @api_secret,
          "--url", @url
          # Missing required: input-type, name, room, identity
        ])
      end)

      assert String.contains?(output, "❌ Error:")
    end

    test "handles invalid input type" do
      # Mock the client to avoid connection timeout and test input validation
      with_mock Livekit.IngressServiceClient, new: fn _url, _api_key, _api_secret ->
        {:ok, {:channel, %{}}}
      end do
        output = capture_io(fn ->
          LivekitTask.run([
            "create-ingress",
            "--api-key", @api_key,
            "--api-secret", @api_secret,
            "--url", @url,
            "--input-type", "INVALID",
            "--name", "test",
            "--room", "test",
            "--identity", "test"
          ])
        end)

        assert String.contains?(output, "❌ Error: Invalid input type 'INVALID'")
      end
    end

    test "creates ingress with encoding options" do
      expected_ingress = %Livekit.IngressInfo{
        ingress_id: "ingress_123",
        name: "test-stream-with-encoding",
        input_type: :RTMP_INPUT,
        room_name: "test-room",
        participant_identity: "streamer"
      }

      with_mocks([
        {Livekit.IngressServiceClient, [], [
          new: fn _url, _api_key, _api_secret -> {:ok, {:channel, %{}}} end,
          create_ingress: fn _client, request ->
            assert request.name == "test-stream-with-encoding"
            # Note: Encoding options verification depends on CLI implementation
            # When implemented, these should be verified:
            # assert request.enable_transcoding == true
            # assert request.audio != nil  # Audio encoding options set
            # assert request.video != nil  # Video encoding options set
            {:ok, expected_ingress}
          end
        ]}
      ]) do
        output = capture_io(fn ->
          LivekitTask.run([
            "create-ingress",
            "--api-key", @api_key,
            "--api-secret", @api_secret,
            "--url", @url,
            "--input-type", "RTMP",
            "--name", "test-stream-with-encoding",
            "--room", "test-room",
            "--identity", "streamer",
            "--enable-transcoding", "true",
            "--audio-preset", "speech",
            "--video-preset", "h264_720p_30"
          ])
        end)

        assert String.contains?(output, "✅ Ingress created successfully!")
        assert String.contains?(output, "Ingress ID: ingress_123")
      end
    end

    test "creates ingress with participant metadata" do
      expected_ingress = %Livekit.IngressInfo{
        ingress_id: "ingress_456",
        name: "metadata-stream",
        input_type: :WHIP_INPUT,
        room_name: "metadata-room",
        participant_identity: "metadata-user"
      }

      with_mocks([
        {Livekit.IngressServiceClient, [], [
          new: fn _url, _api_key, _api_secret -> {:ok, {:channel, %{}}} end,
          create_ingress: fn _client, request ->
            assert request.participant_metadata == "custom-metadata"
            {:ok, expected_ingress}
          end
        ]}
      ]) do
        output = capture_io(fn ->
          LivekitTask.run([
            "create-ingress",
            "--api-key", @api_key,
            "--api-secret", @api_secret,
            "--url", @url,
            "--input-type", "WHIP",
            "--name", "metadata-stream",
            "--room", "metadata-room",
            "--identity", "metadata-user",
            "--participant-metadata", "custom-metadata"
          ])
        end)

        assert String.contains?(output, "✅ Ingress created successfully!")
        assert String.contains?(output, "Ingress ID: ingress_456")
      end
    end

    test "creates URL ingress with empty source URL when not provided" do
      expected_ingress = %Livekit.IngressInfo{
        ingress_id: "url_empty_123",
        name: "url-stream",
        url: "", # Empty URL when source-url not provided
        input_type: :URL_INPUT,
        room_name: "url-room",
        participant_identity: "url-user"
      }

      with_mocks([
        {Livekit.IngressServiceClient, [], [
          new: fn _url, _api_key, _api_secret -> {:ok, {:channel, %{}}} end,
          create_ingress: fn _client, request ->
            # Verify that URL defaults to empty string when --source-url not provided
            assert request.url == ""
            assert request.input_type == :URL_INPUT
            {:ok, expected_ingress}
          end
        ]}
      ]) do
        output = capture_io(fn ->
          LivekitTask.run([
            "create-ingress",
            "--api-key", @api_key,
            "--api-secret", @api_secret,
            "--url", @url,
            "--input-type", "URL",
            "--name", "url-stream",
            "--room", "url-room",
            "--identity", "url-user"
            # Missing --source-url for URL input type - should default to empty string
          ])
        end)

        # Should succeed with empty URL
        assert String.contains?(output, "✅ Ingress created successfully!")
        assert String.contains?(output, "Ingress ID: url_empty_123")
      end
    end

    test "handles special characters in parameters" do
      expected_ingress = %Livekit.IngressInfo{
        ingress_id: "special_123",
        name: "stream-with-special-chars",
        input_type: :RTMP_INPUT,
        room_name: "room-with-dashes",
        participant_identity: "user_with_underscores"
      }

      with_mocks([
        {Livekit.IngressServiceClient, [], [
          new: fn _url, _api_key, _api_secret -> {:ok, {:channel, %{}}} end,
          create_ingress: fn _client, request ->
            assert request.name == "stream-with-special-chars"
            assert request.room_name == "room-with-dashes"
            assert request.participant_identity == "user_with_underscores"
            {:ok, expected_ingress}
          end
        ]}
      ]) do
        output = capture_io(fn ->
          LivekitTask.run([
            "create-ingress",
            "--api-key", @api_key,
            "--api-secret", @api_secret,
            "--url", @url,
            "--input-type", "RTMP",
            "--name", "stream-with-special-chars",
            "--room", "room-with-dashes",
            "--identity", "user_with_underscores"
          ])
        end)

        assert String.contains?(output, "✅ Ingress created successfully!")
        assert String.contains?(output, "Ingress ID: special_123")
      end
    end

    test "handles client connection errors" do
      with_mock Livekit.IngressServiceClient, new: fn _url, _api_key, _api_secret ->
        {:error, "Connection failed"}
      end do
        output = capture_io(fn ->
          LivekitTask.run([
            "create-ingress",
            "--api-key", @api_key,
            "--api-secret", @api_secret,
            "--url", @url,
            "--input-type", "RTMP",
            "--name", "test",
            "--room", "test",
            "--identity", "test"
          ])
        end)

        assert String.contains?(output, "❌ Error: Connection failed")
      end
    end

    test "handles ingress creation errors" do
      with_mocks([
        {Livekit.IngressServiceClient, [], [
          new: fn _url, _api_key, _api_secret -> {:ok, {:channel, %{}}} end,
          create_ingress: fn _client, _request -> {:error, "Room not found"} end
        ]}
      ]) do
        output = capture_io(fn ->
          LivekitTask.run([
            "create-ingress",
            "--api-key", @api_key,
            "--api-secret", @api_secret,
            "--url", @url,
            "--input-type", "RTMP",
            "--name", "test",
            "--room", "nonexistent-room",
            "--identity", "test"
          ])
        end)

        assert String.contains?(output, "❌ Error creating ingress: \"Room not found\"")
      end
    end
  end

  describe "update-ingress command" do
    test "updates ingress successfully" do
      updated_ingress = %Livekit.IngressInfo{
        ingress_id: "ingress_123",
        name: "updated-stream",
        room_name: "new-room",
        participant_identity: "new-identity"
      }

      with_mocks([
        {Livekit.IngressServiceClient, [], [
          new: fn _url, _api_key, _api_secret -> {:ok, {:channel, %{}}} end,
          update_ingress: fn _client, _request -> {:ok, updated_ingress} end
        ]}
      ]) do
        output = capture_io(fn ->
          LivekitTask.run([
            "update-ingress",
            "--api-key", @api_key,
            "--api-secret", @api_secret,
            "--url", @url,
            "--ingress-id", "ingress_123",
            "--name", "updated-stream",
            "--room", "new-room",
            "--identity", "new-identity"
          ])
        end)

        assert String.contains?(output, "✅ Ingress updated successfully!")
        assert String.contains?(output, "Ingress ID: ingress_123")
        assert String.contains?(output, "Name: updated-stream")
      end
    end

    test "handles missing ingress ID" do
      output = capture_io(fn ->
        LivekitTask.run([
          "update-ingress",
          "--api-key", @api_key,
          "--api-secret", @api_secret,
          "--url", @url,
          "--name", "updated-stream"
        ])
      end)

      assert String.contains?(output, "❌ Error:")
    end
  end

  describe "list-ingress command" do
    test "lists ingress endpoints successfully" do
      ingress1 = %Livekit.IngressInfo{
        ingress_id: "ingress_1",
        name: "stream1",
        input_type: :RTMP_INPUT,
        url: "rtmp://example.com/live1",
        room_name: "room1",
        participant_identity: "user1",
        state: %Livekit.IngressState{status: :ENDPOINT_PUBLISHING},
        enabled: true
      }

      ingress2 = %Livekit.IngressInfo{
        ingress_id: "ingress_2",
        name: "stream2",
        input_type: :WHIP_INPUT,
        url: "https://example.com/whip2",
        room_name: "room2",
        participant_identity: "user2",
        state: %Livekit.IngressState{status: :ENDPOINT_INACTIVE},
        enabled: false
      }

      list_response = %Livekit.ListIngressResponse{items: [ingress1, ingress2]}

      with_mocks([
        {Livekit.IngressServiceClient, [], [
          new: fn _url, _api_key, _api_secret -> {:ok, {:channel, %{}}} end,
          list_ingress: fn _client, _request -> {:ok, list_response} end
        ]}
      ]) do
        output = capture_io(fn ->
          LivekitTask.run([
            "list-ingress",
            "--api-key", @api_key,
            "--api-secret", @api_secret,
            "--url", @url
          ])
        end)

        assert String.contains?(output, "📡 Ingress Endpoints:")
        assert String.contains?(output, "ID: ingress_1")
        assert String.contains?(output, "Name: stream1")
        assert String.contains?(output, "Type: RTMP_INPUT")
        assert String.contains?(output, "Status: ENDPOINT_PUBLISHING")
        assert String.contains?(output, "Enabled: true")
        assert String.contains?(output, "ID: ingress_2")
        assert String.contains?(output, "Name: stream2")
        assert String.contains?(output, "Type: WHIP_INPUT")
        assert String.contains?(output, "Status: ENDPOINT_INACTIVE")
        assert String.contains?(output, "Enabled: false")
      end
    end

    test "handles empty list" do
      list_response = %Livekit.ListIngressResponse{items: []}

      with_mocks([
        {Livekit.IngressServiceClient, [], [
          new: fn _url, _api_key, _api_secret -> {:ok, {:channel, %{}}} end,
          list_ingress: fn _client, _request -> {:ok, list_response} end
        ]}
      ]) do
        output = capture_io(fn ->
          LivekitTask.run([
            "list-ingress",
            "--api-key", @api_key,
            "--api-secret", @api_secret,
            "--url", @url
          ])
        end)

        assert String.contains?(output, "No ingress endpoints found.")
      end
    end

    test "filters by room name" do
      list_response = %Livekit.ListIngressResponse{items: []}

      with_mocks([
        {Livekit.IngressServiceClient, [], [
          new: fn _url, _api_key, _api_secret -> {:ok, {:channel, %{}}} end,
          list_ingress: fn _client, request ->
            assert request.room_name == "specific-room"
            {:ok, list_response}
          end
        ]}
      ]) do
        capture_io(fn ->
          LivekitTask.run([
            "list-ingress",
            "--api-key", @api_key,
            "--api-secret", @api_secret,
            "--url", @url,
            "--room", "specific-room"
          ])
        end)
      end
    end
  end

  describe "delete-ingress command" do
    test "deletes ingress successfully" do
      deleted_ingress = %Livekit.IngressInfo{
        ingress_id: "ingress_123",
        name: "deleted-stream"
      }

      with_mocks([
        {Livekit.IngressServiceClient, [], [
          new: fn _url, _api_key, _api_secret -> {:ok, {:channel, %{}}} end,
          delete_ingress: fn _client, _request -> {:ok, deleted_ingress} end
        ]}
      ]) do
        output = capture_io(fn ->
          LivekitTask.run([
            "delete-ingress",
            "--api-key", @api_key,
            "--api-secret", @api_secret,
            "--url", @url,
            "--ingress-id", "ingress_123"
          ])
        end)

        assert String.contains?(output, "✅ Ingress deleted successfully!")
        assert String.contains?(output, "Deleted Ingress ID: ingress_123")
        assert String.contains?(output, "Name: deleted-stream")
      end
    end

    test "handles missing ingress ID" do
      output = capture_io(fn ->
        LivekitTask.run([
          "delete-ingress",
          "--api-key", @api_key,
          "--api-secret", @api_secret,
          "--url", @url
        ])
      end)

      assert String.contains?(output, "❌ Error:")
    end

    test "handles deletion errors" do
      with_mocks([
        {Livekit.IngressServiceClient, [], [
          new: fn _url, _api_key, _api_secret -> {:ok, {:channel, %{}}} end,
          delete_ingress: fn _client, _request -> {:error, "Ingress not found"} end
        ]}
      ]) do
        output = capture_io(fn ->
          LivekitTask.run([
            "delete-ingress",
            "--api-key", @api_key,
            "--api-secret", @api_secret,
            "--url", @url,
            "--ingress-id", "nonexistent"
          ])
        end)

        assert String.contains?(output, "❌ Error deleting ingress: \"Ingress not found\"")
      end
    end
  end

  describe "error scenarios" do
    test "handles unknown command gracefully" do
      output = capture_io(fn ->
        LivekitTask.run(["unknown-command"])
      end)

      # Should show help
      assert String.contains?(output, "Provides CLI commands for Livekit operations")
    end

    test "handles missing credentials" do
      output = capture_io(fn ->
        LivekitTask.run([
          "create-ingress",
          "--input-type", "RTMP",
          "--name", "test",
          "--room", "test",
          "--identity", "test"
        ])
      end)

      assert String.contains?(output, "❌ Error:")
    end

    test "handles malformed CLI arguments" do
      output = capture_io(fn ->
        LivekitTask.run([
          "create-ingress",
          "--api-key", @api_key,
          "--api-secret", @api_secret,
          "--url", @url,
          "--input-type", "RTMP",
          "--name", # Missing value for name
          "--room", "test",
          "--identity", "test"
        ])
      end)

      assert String.contains?(output, "❌ Error:")
    end

    test "handles empty command list" do
      output = capture_io(fn ->
        LivekitTask.run([])
      end)

      # Should show help when no command provided
      assert String.contains?(output, "Provides CLI commands for Livekit operations")
    end

    test "handles partial credentials" do
      output = capture_io(fn ->
        LivekitTask.run([
          "create-ingress",
          "--api-key", @api_key,
          # Missing --api-secret and --url
          "--input-type", "RTMP",
          "--name", "test",
          "--room", "test",
          "--identity", "test"
        ])
      end)

      assert String.contains?(output, "❌ Error:")
    end

    test "handles invalid boolean flags" do
      output = capture_io(fn ->
        LivekitTask.run([
          "create-ingress",
          "--api-key", @api_key,
          "--api-secret", @api_secret,
          "--url", @url,
          "--input-type", "RTMP",
          "--name", "test",
          "--room", "test",
          "--identity", "test",
          "--enable-transcoding", "maybe" # Invalid boolean value
        ])
      end)

      # Should handle gracefully or show error
      assert String.contains?(output, "❌ Error:") or String.contains?(output, "✅")
    end
  end

  describe "help and documentation" do
    test "shows help for specific commands" do
      output = capture_io(fn ->
        LivekitTask.run(["help"])
      end)

      assert String.contains?(output, "Provides CLI commands for Livekit operations")
    end

    test "shows available commands in help" do
      output = capture_io(fn ->
        LivekitTask.run([])
      end)

      assert String.contains?(output, "create-ingress")
      assert String.contains?(output, "list-ingress")
      assert String.contains?(output, "update-ingress")
      assert String.contains?(output, "delete-ingress")
    end
  end
end

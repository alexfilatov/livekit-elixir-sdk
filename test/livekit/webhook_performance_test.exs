defmodule Livekit.WebhookPerformanceTest do
  # Change async to false to avoid conflicts with other tests mocking the same modules
  use ExUnit.Case, async: false

  alias Livekit.AccessToken
  alias Livekit.WebhookReceiver

  import Mock

  @tag :performance
  describe "webhook performance" do
    test "handles large webhook payloads efficiently" do
      # Generate a large room with many participants
      participants =
        Enum.map(1..100, fn i ->
          %{
            "sid" => "PA_test#{i}",
            "identity" => "user#{i}",
            "name" => "Test User #{i}",
            "metadata" =>
              "{\"role\":\"#{if rem(i, 3) == 0, do: "presenter", else: "attendee"}\"}",
            "state" => "ACTIVE",
            "joinedAt" => 1_613_443_597 + i,
            "permission" => %{
              "canPublish" => true,
              "canSubscribe" => true,
              "canPublishData" => true
            },
            "tracks" =>
              Enum.map(1..3, fn j ->
                %{
                  "sid" => "TR_test#{i}_#{j}",
                  "type" =>
                    if rem(j, 2) == 0 do
                      "AUDIO"
                    else
                      "VIDEO"
                    end,
                  "name" =>
                    if rem(j, 2) == 0 do
                      "microphone"
                    else
                      "camera"
                    end,
                  "muted" => false,
                  "width" =>
                    if rem(j, 2) == 0 do
                      0
                    else
                      1280
                    end,
                  "height" =>
                    if rem(j, 2) == 0 do
                      0
                    else
                      720
                    end,
                  "simulcast" => rem(j, 2) != 0,
                  "disableDtx" => false,
                  "source" =>
                    if rem(j, 2) == 0 do
                      "MICROPHONE"
                    else
                      "CAMERA"
                    end
                }
              end)
          }
        end)

      # Create a large room with complex metadata
      room = %{
        "name" => "large-test-room",
        "sid" => "RM_test123",
        "emptyTimeout" => 300,
        "maxParticipants" => 200,
        "creationTime" => 1_613_443_500,
        "turnPassword" => "password123",
        "enabledCodecs" =>
          Enum.map(1..10, fn i ->
            %{"mime" => "audio/opus#{i}", "fmtpLine" => "minptime=10;useinbandfec=1"}
          end),
        "metadata" =>
          Jason.encode!(%{
            "session" => "regular",
            "settings" => %{
              "recording" => true,
              "quality" => "high",
              "layout" => %{
                "grid" => true,
                "maxTiles" => 16,
                "screenShareMode" => "sideBySide"
              },
              "permissions" => %{
                "canRecord" => true,
                "canTranscribe" => true,
                "canDrawOnWhiteboard" => true
              }
            },
            "features" => %{
              "chat" => true,
              "whiteboard" => true,
              "breakoutRooms" => true,
              "polling" => true
            },
            "branding" => %{
              "logo" => "https://example.com/logo.png",
              "colors" => %{
                "primary" => "#FF5733",
                "secondary" => "#33FF57",
                "accent" => "#5733FF"
              }
            }
          }),
        "numParticipants" => length(participants),
        "activeRecording" => true,
        "participants" => participants
      }

      # Create the webhook payload with the large room and participant list
      webhook_body =
        Jason.encode!(%{
          "event" => "room_updated",
          "room" => room,
          "participants" => participants,
          "id" => "123",
          "createdAt" => 1_613_443_597
        })

      # Create a mock token
      token = "mock_token"

      # Calculate SHA256 hash of the body
      sha256 = :crypto.hash(:sha256, webhook_body) |> Base.encode16(case: :lower)

      # Mock the application config
      Application.put_env(:livekit, :webhook, %{
        api_key: "test_key",
        api_secret: "test_secret"
      })

      # Mock the token verification
      with_mock AccessToken,
        verify: fn ^token, "test_key", "test_secret" -> {:ok, %{"sha256" => sha256}} end do
        # Measure the time it takes to process the webhook
        {time, result} =
          :timer.tc(fn ->
            WebhookReceiver.receive(webhook_body, token)
          end)

        # Convert microseconds to milliseconds for better readability
        time_ms = time / 1000

        # Log the time it took to process the webhook
        IO.puts("Large webhook processing time: #{time_ms} ms")

        # Assertions
        assert {:ok, event} = result
        assert event.event == "room_updated"
        assert event.room.name == "large-test-room"
        assert event.room.sid == "RM_test123"

        # Ensure processing time is reasonable (adjust threshold as needed)
        # This is a soft assertion as performance can vary by environment
        assert time_ms < 1000, "Webhook processing took too long: #{time_ms} ms"
      end
    end

    @tag :performance
    test "handles malformed but valid JSON efficiently" do
      # Create a webhook payload with unusual but valid JSON structure
      webhook_body = ~s({
        "event": "room_created",
        "room": {
          "name": "test-room",
          "sid": "RM_test123",
          "emptyTimeout": 300,
          "maxParticipants": 20,
          "creationTime": 1613443500,
          "metadata": "{\\\"custom\\\":true,\\\"settings\\\":{\\\"recording\\\":true,\\\"quality\\\":\\\"high\\\"}}"
        },
        "id": "123",
        "createdAt": 1613443597
      })

      # Create a mock token
      token = "mock_token"

      # Calculate SHA256 hash of the body
      sha256 = :crypto.hash(:sha256, webhook_body) |> Base.encode16(case: :lower)

      # Mock the application config
      Application.put_env(:livekit, :webhook, %{
        api_key: "test_key",
        api_secret: "test_secret"
      })

      # Mock the token verification
      with_mock AccessToken,
        verify: fn ^token, "test_key", "test_secret" -> {:ok, %{"sha256" => sha256}} end do
        # Measure the time it takes to process the webhook
        {time, result} =
          :timer.tc(fn ->
            WebhookReceiver.receive(webhook_body, token)
          end)

        # Convert microseconds to milliseconds for better readability
        time_ms = time / 1000

        # Log the time it took to process the webhook
        IO.puts("Malformed JSON webhook processing time: #{time_ms} ms")

        # Assertions
        assert {:ok, event} = result
        assert event.event == "room_created"
        assert event.room.name == "test-room"
        assert event.room.sid == "RM_test123"

        # Ensure processing time is reasonable (adjust threshold as needed)
        assert time_ms < 500, "Webhook processing took too long: #{time_ms} ms"
      end
    end

    @tag :performance
    test "handles malformed webhook request efficiently" do
      # Setup
      webhook_body = "This is not valid JSON at all!"

      # Create a mock token
      token = "mock_token"

      # Mock the application config
      Application.put_env(:livekit, :webhook, %{
        api_key: "test_key",
        api_secret: "test_secret"
      })

      # Calculate the time it takes to process the malformed webhook
      {time, result} =
        :timer.tc(fn ->
          # Mock the token verification
          with_mock AccessToken,
            verify: fn ^token, "test_key", "test_secret" -> {:ok, %{"sha256" => "any_hash"}} end do
            # Process the webhook
            WebhookReceiver.receive(webhook_body, token)
          end
        end)

      # Convert time from microseconds to milliseconds
      time_ms = time / 1000

      # Log the time
      IO.puts("Completely malformed webhook processing time: #{time_ms} ms")

      # Assertions
      assert {:error, _} = result
      assert time_ms < 50, "Processing a completely malformed webhook should be relatively quick"
    end
  end
end

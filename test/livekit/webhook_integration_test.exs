defmodule Livekit.WebhookIntegrationTest do
  # Change async to false to avoid conflicts with other tests mocking the same modules
  use ExUnit.Case, async: false

  alias Livekit.WebhookReceiver
  alias Livekit.AccessToken

  import Mock

  # Simulate a Phoenix controller for webhook handling
  defmodule TestWebhookController do
    def handle_webhook(body, auth_header) do
      case Livekit.WebhookReceiver.receive(body, auth_header) do
        {:ok, event} ->
          # Process the event based on its type
          process_webhook_event(event)
          {:ok, 200, %{success: true}}

        {:error, reason} ->
          {:error, 400, %{error: reason}}
      end
    end

    defp process_webhook_event(event) do
      case event.event do
        "room_created" -> handle_room_created(event.room)
        "participant_joined" -> handle_participant_joined(event.participant, event.room)
        "track_published" -> handle_track_published(event.track, event.participant, event.room)
        "egress_started" -> handle_egress_started(event.egress_info)
        "room_finished" -> handle_room_finished(event.room)
        _ -> :ok
      end
    end

    defp handle_room_created(room) do
      # In a real application, this would do something with the room data
      # For testing, we'll just return the room data
      {:room_created, room}
    end

    defp handle_participant_joined(participant, room) do
      # In a real application, this would do something with the participant and room data
      # For testing, we'll just return the participant and room data
      {:participant_joined, participant, room}
    end

    defp handle_track_published(track, participant, room) do
      # In a real application, this would do something with the track, participant, and room data
      # For testing, we'll just return the track, participant, and room data
      {:track_published, track, participant, room}
    end

    defp handle_egress_started(egress_info) do
      # In a real application, this would do something with the egress info data
      # For testing, we'll just return the egress info data
      {:egress_started, egress_info}
    end

    defp handle_room_finished(room) do
      # In a real application, this would do something with the room data
      # For testing, we'll just return the room data
      {:room_finished, room}
    end
  end

  describe "webhook integration" do
    test "successfully processes a room_created webhook" do
      # Setup - Use Jason.encode! to ensure valid JSON
      webhook_body =
        Jason.encode!(%{
          "event" => "room_created",
          "room" => %{"name" => "test-room", "sid" => "RM_test123"},
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
        # Test
        result = TestWebhookController.handle_webhook(webhook_body, token)

        # Assertions
        assert {:ok, 200, %{success: true}} = result
      end
    end

    test "successfully processes a participant_joined webhook" do
      # Setup - Use Jason.encode! to ensure valid JSON
      webhook_body =
        Jason.encode!(%{
          "event" => "participant_joined",
          "room" => %{"name" => "test-room", "sid" => "RM_test123"},
          "participant" => %{
            "sid" => "PA_test123",
            "identity" => "user123",
            "name" => "Test User",
            "metadata" => "{\"role\":\"presenter\"}",
            "state" => "ACTIVE",
            "joinedAt" => 1_613_443_597
          },
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
        # Test
        result = TestWebhookController.handle_webhook(webhook_body, token)

        # Assertions
        assert {:ok, 200, %{success: true}} = result
      end
    end

    test "successfully processes a track_published webhook" do
      # Setup - Use Jason.encode! to ensure valid JSON
      webhook_body =
        Jason.encode!(%{
          "event" => "track_published",
          "room" => %{"name" => "test-room", "sid" => "RM_test123"},
          "participant" => %{
            "sid" => "PA_test123",
            "identity" => "user123",
            "name" => "Test User"
          },
          "track" => %{
            "sid" => "TR_test123",
            "type" => "AUDIO",
            "name" => "microphone",
            "muted" => false,
            "width" => 0,
            "height" => 0,
            "simulcast" => false,
            "disableDtx" => false,
            "source" => "MICROPHONE"
          },
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
        # Test
        result = TestWebhookController.handle_webhook(webhook_body, token)

        # Assertions
        assert {:ok, 200, %{success: true}} = result
      end
    end

    test "handles invalid webhook request" do
      # Setup
      webhook_body = "invalid json"
      token = "mock_token"

      # Mock the application config
      Application.put_env(:livekit, :webhook, %{
        api_key: "test_key",
        api_secret: "test_secret"
      })

      # Calculate SHA256 hash of the body
      sha256 = :crypto.hash(:sha256, webhook_body) |> Base.encode16(case: :lower)

      # Mock the token verification
      with_mock AccessToken,
        verify: fn ^token, "test_key", "test_secret" -> {:ok, %{"sha256" => sha256}} end do
        # Test
        result = TestWebhookController.handle_webhook(webhook_body, token)

        # Assertions
        assert {:error, 400, %{error: _}} = result
      end
    end

    test "handles authentication failure" do
      # Setup - Use Jason.encode! to ensure valid JSON
      webhook_body =
        Jason.encode!(%{
          "event" => "room_created",
          "room" => %{"name" => "test-room", "sid" => "RM_test123"},
          "id" => "123",
          "createdAt" => 1_613_443_597
        })

      # Create a mock token
      token = "invalid_token"

      # Mock the application config
      Application.put_env(:livekit, :webhook, %{
        api_key: "test_key",
        api_secret: "test_secret"
      })

      # Mock the token verification to fail
      with_mock AccessToken,
        verify: fn ^token, "test_key", "test_secret" -> {:error, "invalid token"} end do
        # Test
        result = TestWebhookController.handle_webhook(webhook_body, token)

        # Assertions
        assert {:error, 400, %{error: _}} = result
      end
    end

    test "handles multiple webhook events in sequence" do
      # Mock the application config
      Application.put_env(:livekit, :webhook, %{
        api_key: "test_key",
        api_secret: "test_secret"
      })

      # Create a sequence of webhook events
      webhook_events = [
        %{
          body:
            Jason.encode!(%{
              "event" => "room_created",
              "room" => %{"name" => "test-room", "sid" => "RM_test123"},
              "id" => "123",
              "createdAt" => 1_613_443_597
            }),
          token: "token1"
        },
        %{
          body:
            Jason.encode!(%{
              "event" => "participant_joined",
              "room" => %{"name" => "test-room", "sid" => "RM_test123"},
              "participant" => %{
                "sid" => "PA_test123",
                "identity" => "user123",
                "name" => "Test User",
                "state" => "ACTIVE",
                "joinedAt" => 1_613_443_597
              },
              "id" => "124",
              "createdAt" => 1_613_443_598
            }),
          token: "token2"
        },
        %{
          body:
            Jason.encode!(%{
              "event" => "track_published",
              "room" => %{"name" => "test-room", "sid" => "RM_test123"},
              "participant" => %{
                "sid" => "PA_test123",
                "identity" => "user123",
                "name" => "Test User"
              },
              "track" => %{
                "sid" => "TR_test123",
                "type" => "AUDIO",
                "name" => "microphone",
                "muted" => false
              },
              "id" => "125",
              "createdAt" => 1_613_443_599
            }),
          token: "token3"
        }
      ]

      # Process each event in sequence
      Enum.each(webhook_events, fn %{body: webhook_body, token: token} ->
        # Calculate SHA256 hash of the body
        sha256 = :crypto.hash(:sha256, webhook_body) |> Base.encode16(case: :lower)

        # Mock the token verification
        with_mock AccessToken,
          verify: fn ^token, "test_key", "test_secret" -> {:ok, %{"sha256" => sha256}} end do
          # Test
          result = TestWebhookController.handle_webhook(webhook_body, token)

          # Assertions
          assert {:ok, 200, %{success: true}} = result

          # Verify the event was processed correctly
          {:ok, event} = WebhookReceiver.decode_event(webhook_body)
          assert event.event in ["room_created", "participant_joined", "track_published"]
        end
      end)
    end

    test "successfully processes an egress_started webhook" do
      # Setup - Use Jason.encode! to ensure valid JSON
      webhook_body =
        Jason.encode!(%{
          "event" => "egress_started",
          "room" => %{"name" => "test-room", "sid" => "RM_test123"},
          "egressInfo" => %{
            "egressId" => "EG_test123",
            "roomId" => "RM_test123",
            "roomName" => "test-room",
            "status" => "EGRESS_ACTIVE",
            "startedAt" => 1_613_443_597,
            "resourceId" => "resource123",
            "file" => %{
              "filepath" => "/recordings/test.mp4",
              "filesize" => 1024,
              "filename" => "test.mp4",
              "startedAt" => 1_613_443_597,
              "endedAt" => 0
            }
          },
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
        # Test
        result = TestWebhookController.handle_webhook(webhook_body, token)

        # Assertions
        assert {:ok, 200, %{success: true}} = result

        # Verify the event was decoded correctly
        {:ok, event} = WebhookReceiver.decode_event(webhook_body)
        assert event.event == "egress_started"
        assert event.egress_info.egress_id == "EG_test123"
        # EGRESS_ACTIVE is represented as 2 in the enum
        assert event.egress_info.status == 2
      end
    end

    test "successfully processes a room_finished webhook" do
      # Setup - Use Jason.encode! to ensure valid JSON
      webhook_body =
        Jason.encode!(%{
          "event" => "room_finished",
          "room" => %{
            "name" => "test-room",
            "sid" => "RM_test123",
            "emptyTimeout" => 300,
            "maxParticipants" => 20,
            "creationTime" => 1_613_443_500,
            "endedAt" => 1_613_443_800,
            "metadata" => "{\"session\":\"completed\"}"
          },
          "id" => "123",
          "createdAt" => 1_613_443_800
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
        # Test
        result = TestWebhookController.handle_webhook(webhook_body, token)

        # Assertions
        assert {:ok, 200, %{success: true}} = result

        # Verify the event was decoded correctly
        {:ok, event} = WebhookReceiver.decode_event(webhook_body)
        assert event.event == "room_finished"
        assert event.room.name == "test-room"
        assert event.room.sid == "RM_test123"
      end
    end
  end
end

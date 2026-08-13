defmodule Livekit.WebRTC.Integration.RoomIntegrationTest do
  @moduledoc """
  Integration tests for LiveKit WebRTC room connection (D-20, D-21).

  ## Prerequisites

  These tests require a running LiveKit server. Start one locally via docker-compose:

      cd examples/docker
      docker-compose up -d

  Then set environment variables before running:

      LIVEKIT_URL=ws://localhost:7880 \\
      LIVEKIT_API_KEY=devkey \\
      LIVEKIT_API_SECRET=secret \\
        mix test --only integration

  ## Audio round-trip test (D-21)

  The `audio_round_trip` test publishes PCM audio from one agent participant
  and verifies the frames are received by a second subscriber participant
  in the same room. Both participants are Elixir processes in the same test.
  """

  use ExUnit.Case, async: false

  @moduletag :integration

  alias Livekit.{AccessToken, Grants}
  alias Livekit.Agents.AudioFrame
  alias Livekit.WebRTC.{AudioTrack, Room}

  @livekit_url System.get_env("LIVEKIT_URL", "ws://localhost:7880")
  @api_key System.get_env("LIVEKIT_API_KEY", "devkey")
  @api_secret System.get_env("LIVEKIT_API_SECRET", "secret")
  @test_room "integration-test-room"

  defp make_token(identity) do
    AccessToken.new(@api_key, @api_secret)
    |> AccessToken.with_identity(identity)
    |> AccessToken.with_grants(%Grants{room_join: true, room: @test_room})
    |> AccessToken.to_jwt()
  end

  # These tests only run with `mix test --only integration`.
  # If the LiveKit server is not running, tests will fail with a connection error.
  # Start the server first: cd examples/docker && docker-compose up -d

  describe "room connection" do
    test "connects and receives participant_connected event when second participant joins" do
      publisher_token = make_token("publisher-agent")
      subscriber_token = make_token("subscriber-agent")

      {:ok, publisher} =
        Room.connect(%Room.Config{
          url: @livekit_url,
          token: publisher_token
        })

      Room.subscribe_events(publisher, self())

      {:ok, _subscriber} =
        Room.connect(%Room.Config{
          url: @livekit_url,
          token: subscriber_token
        })

      assert_receive {:participant_connected, "subscriber-agent"}, 5_000

      Room.disconnect(publisher)
    end
  end

  describe "audio round-trip (D-21)" do
    test "publishes PCM frame from one participant and receives it via second subscriber" do
      publisher_token = make_token("audio-publisher")
      subscriber_token = make_token("audio-subscriber")

      # Publisher room
      {:ok, publisher_room} =
        Room.connect(%Room.Config{
          url: @livekit_url,
          token: publisher_token
        })

      # Subscriber room — listens for track_subscribed event
      {:ok, subscriber_room} =
        Room.connect(%Room.Config{
          url: @livekit_url,
          token: subscriber_token
        })

      Room.subscribe_events(subscriber_room, self())

      # Publish a 10ms PCM frame (480 samples at 48kHz mono = 960 bytes of int16)
      silence_frame =
        AudioFrame.new(
          :binary.copy(<<0, 0>>, 480),
          sample_rate: 48_000,
          channels: 1,
          format: :pcm_16
        )

      :ok = AudioTrack.publish(publisher_room, silence_frame)

      # Subscriber should receive track_subscribed (auto_subscribe: true in RoomOptions)
      assert_receive {:track_subscribed, track_sid, "audio-publisher", "Audio"}, 5_000

      # Every later frame must go into the same track. A track per frame is not a
      # stream anybody can listen to — that was the bug.
      :ok = AudioTrack.publish(publisher_room, silence_frame)
      :ok = AudioTrack.publish(publisher_room, silence_frame)
      refute_receive {:track_subscribed, _sid, "audio-publisher", "Audio"}, 2_000

      # Now subscribe to the audio stream
      {:ok, _track_ref} = AudioTrack.subscribe(subscriber_room, track_sid, self())

      # Should receive audio frames
      assert_receive {:audio_frame, ^track_sid, binary}, 5_000
      assert is_binary(binary)
      assert rem(byte_size(binary), 2) == 0, "Audio binary must be even bytes (int16 LE)"

      Room.disconnect(publisher_room)
      Room.disconnect(subscriber_room)
    end
  end
end

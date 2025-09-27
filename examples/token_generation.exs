Mix.install([
  {:livekit, path: "."},
  {:jason, "~> 1.4"},
  {:twirp, "~> 0.8.0"}
])

alias Livekit.AccessToken
alias Livekit.AccessToken.VideoGrants

# Configure Livekit credentials
api_key = "devkey"
api_secret = "secret"

# Example 1: Generate a token for a participant to join a room
IO.puts("\n=== Generating token for room participant ===\n")

participant_token =
  AccessToken.new(api_key, api_secret)
  # Unique identifier for the participant
  |> AccessToken.with_identity("participant-123")
  # Token valid for 1 hour
  |> AccessToken.with_ttl(3600)
  # Optional metadata
  |> AccessToken.with_metadata(%{name: "John Doe"} |> Jason.encode!())
  # Grant permission to join "my-room"
  |> AccessToken.add_grant(VideoGrants.join_room("my-room"))
  |> AccessToken.to_jwt()

IO.puts("Participant token: #{participant_token}\n")

# Example 2: Generate a token with publish-only permissions
IO.puts("\n=== Generating token for publisher ===\n")

publisher_token =
  AccessToken.new(api_key, api_secret)
  |> AccessToken.with_identity("publisher-456")
  |> AccessToken.with_ttl(3600)
  # Basic room join permission
  |> AccessToken.add_grant(VideoGrants.join_room("my-room"))
  # Add recording permission
  |> AccessToken.add_grant(VideoGrants.room_record())
  |> AccessToken.to_jwt()

IO.puts("Publisher token: #{publisher_token}\n")

# Example 3: Generate a token with subscribe-only permissions
IO.puts("\n=== Generating token for subscriber ===\n")

subscriber_token =
  AccessToken.new(api_key, api_secret)
  |> AccessToken.with_identity("subscriber-789")
  |> AccessToken.with_ttl(3600)
  # Only basic room join permission
  |> AccessToken.add_grant(VideoGrants.join_room("my-room"))
  |> AccessToken.to_jwt()

IO.puts("Subscriber token: #{subscriber_token}\n")

# Example 4: Generate a token for a room moderator
IO.puts("\n=== Generating token for room moderator ===\n")

moderator_token =
  AccessToken.new(api_key, api_secret)
  |> AccessToken.with_identity("moderator-012")
  |> AccessToken.with_ttl(3600)
  # Basic room join permission
  |> AccessToken.add_grant(VideoGrants.join_room("my-room"))
  # Add admin permission
  |> AccessToken.add_grant(VideoGrants.room_admin())
  |> AccessToken.to_jwt()

IO.puts("Moderator token: #{moderator_token}\n")

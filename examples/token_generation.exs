Mix.install([
  {:livekit, path: "."},
  {:jason, "~> 1.4"},
  {:twirp, "~> 0.8.0"}
])

alias LiveKit.AccessToken
alias LiveKit.Grants

# Configure LiveKit credentials
api_key = "devkey"
api_secret = "secret"

# Example 1: Generate a token for a participant to join a room
IO.puts("\n=== Generating token for room participant ===\n")

participant_token = AccessToken.new(api_key, api_secret)
|> AccessToken.with_identity("participant-123")  # Unique identifier for the participant
|> AccessToken.with_ttl(3600)  # Token valid for 1 hour
|> AccessToken.with_metadata(%{name: "John Doe"} |> Jason.encode!())  # Optional metadata
|> AccessToken.add_grant(Grants.join_room("my-room"))  # Grant permission to join "my-room"
|> AccessToken.to_jwt()

IO.puts("Participant token: #{participant_token}\n")

# Example 2: Generate a token with publish-only permissions
IO.puts("\n=== Generating token for publisher ===\n")

publisher_token = AccessToken.new(api_key, api_secret)
|> AccessToken.with_identity("publisher-456")
|> AccessToken.with_ttl(3600)
|> AccessToken.add_grant(Grants.join_room("my-room"))  # Basic room join permission
|> AccessToken.add_grant(Grants.room_record())  # Add recording permission
|> AccessToken.to_jwt()

IO.puts("Publisher token: #{publisher_token}\n")

# Example 3: Generate a token with subscribe-only permissions
IO.puts("\n=== Generating token for subscriber ===\n")

subscriber_token = AccessToken.new(api_key, api_secret)
|> AccessToken.with_identity("subscriber-789")
|> AccessToken.with_ttl(3600)
|> AccessToken.add_grant(Grants.join_room("my-room"))  # Only basic room join permission
|> AccessToken.to_jwt()

IO.puts("Subscriber token: #{subscriber_token}\n")

# Example 4: Generate a token for a room moderator
IO.puts("\n=== Generating token for room moderator ===\n")

moderator_token = AccessToken.new(api_key, api_secret)
|> AccessToken.with_identity("moderator-012")
|> AccessToken.with_ttl(3600)
|> AccessToken.add_grant(Grants.join_room("my-room"))  # Basic room join permission
|> AccessToken.add_grant(Grants.room_admin())  # Add admin permission
|> AccessToken.to_jwt()

IO.puts("Moderator token: #{moderator_token}\n")

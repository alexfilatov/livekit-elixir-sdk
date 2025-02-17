Mix.install([
  {:livekit, path: "."},
  {:jason, "~> 1.4"}
])

# Configure Livekit credentials
api_key = "devkey"
api_secret = "secret"
livekit_url = "http://localhost:7880"

# Create a client instance
client = Livekit.RoomServiceClient.new(livekit_url, api_key, api_secret)

# Create a test room
{:ok, room} = Livekit.RoomServiceClient.create_room(client, "test-room")
IO.puts("\nCreated room: #{room.name}\n")

# Example 1: Update participant metadata and attributes
IO.puts("=== Updating participant information ===\n")
{:ok, updated_participant} = Livekit.RoomServiceClient.update_participant(
  client,
  "test-room",
  "participant-123",
  metadata: Jason.encode!(%{role: "presenter"}),
  name: "John Doe",
  attributes: %{
    "avatar" => "https://example.com/avatar.jpg",
    "title" => "Senior Engineer"
  }
)

IO.inspect(updated_participant, label: "Updated participant")

# Example 2: Update track subscriptions
IO.puts("\n=== Updating track subscriptions ===\n")
:ok = Livekit.RoomServiceClient.update_subscriptions(
  client,
  "test-room",
  "participant-123",
  ["track-1", "track-2"],  # track_sids to update
  true  # subscribe = true to subscribe, false to unsubscribe
)

IO.puts("Successfully updated track subscriptions")

# Example 3: Send data to specific participants
IO.puts("\n=== Sending data to participants ===\n")

# Send to specific participants by identity
:ok = Livekit.RoomServiceClient.send_data(
  client,
  "test-room",
  "Hello specific participants!",
  :RELIABLE,  # or :LOSSY for unreliable delivery
  destination_identities: ["participant-1", "participant-2"]
)

IO.puts("Sent data to specific participants")

# Broadcast to all participants in the room
:ok = Livekit.RoomServiceClient.send_data(
  client,
  "test-room",
  "Hello everyone!",
  :RELIABLE
)

IO.puts("Broadcasted data to all participants")

# Clean up: Delete the test room
:ok = Livekit.RoomServiceClient.delete_room(client, "test-room")
IO.puts("\nDeleted test room")

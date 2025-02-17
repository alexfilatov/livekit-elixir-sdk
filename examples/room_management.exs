Mix.install([
  {:livekit, path: "."},
  {:jason, "~> 1.4"},
  {:twirp, "~> 0.8.0"}
])

alias Livekit.RoomServiceClient

# Configure Livekit server URL and credentials
api_key = "devkey"
api_secret = "secret"
livekit_url = "http://localhost:7880"

# Create a new RoomServiceClient
client = RoomServiceClient.new(livekit_url, api_key, api_secret)

# Create a new room
IO.puts("\n=== Creating a new room ===\n")
room_name = "test-room-#{:rand.uniform(1000)}"

case RoomServiceClient.create_room(client, room_name, empty_timeout: 600, max_participants: 10) do
  {:ok, room} ->
    IO.puts("Room created successfully:")
    IO.puts("  Name: #{room.name}")
    IO.puts("  SID: #{room.sid}")
    IO.puts("  Empty timeout: #{room.empty_timeout} seconds")
    IO.puts("  Max participants: #{room.max_participants}")
    IO.puts("  Number of participants: #{room.num_participants}")
    IO.puts("  Active recording: #{room.active_recording}")
    IO.puts("  Enabled codecs:")
    Enum.each(room.enabled_codecs, fn codec -> IO.puts("    - #{codec.mime}") end)

  {:error, error} ->
    IO.puts("Failed to create room: #{inspect(error)}")
end

# Update room metadata
IO.puts("\n=== Updating room metadata ===\n")

case RoomServiceClient.update_room_metadata(client, room_name, "test metadata") do
  {:ok, room} ->
    IO.puts("Room metadata updated successfully:")
    IO.puts("  Name: #{room.name}")
    IO.puts("  SID: #{room.sid}")
    IO.puts("  Metadata: #{room.metadata}")

  {:error, error} ->
    IO.puts("Failed to update room metadata: #{inspect(error)}")
end

# List participants in the room
IO.puts("\nParticipants in room #{room_name}:\n")

case RoomServiceClient.list_participants(client, room_name) do
  {:ok, response} ->
    if Enum.empty?(response.participants) do
      IO.puts("No participants in the room")
    else
      Enum.each(response.participants, fn participant ->
        IO.puts("  - Identity: #{participant.identity}")
        IO.puts("    State: #{participant.state}")
        IO.puts("    Joined at: #{participant.joined_at}")
        IO.puts("")
      end)
    end

  {:error, error} ->
    IO.puts("Failed to list participants: #{inspect(error)}")
end

# List all rooms
IO.puts("\n=== Listing all rooms ===\n")

case RoomServiceClient.list_rooms(client) do
  {:ok, response} ->
    IO.puts("All rooms:")
    Enum.each(response.rooms, fn room ->
      IO.puts("  - Name: #{room.name}")
      IO.puts("    SID: #{room.sid}")
      IO.puts("    Participants: #{room.num_participants}")
    end)

  {:error, error} ->
    IO.puts("Failed to list rooms: #{inspect(error)}")
end

# Delete room
IO.puts("\n=== Deleting room ===\n")

case RoomServiceClient.delete_room(client, room_name) do
  :ok ->
    IO.puts("Room deleted successfully")

  {:error, error} ->
    IO.puts("Failed to delete room: #{inspect(error)}")
end

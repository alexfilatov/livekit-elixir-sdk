# LiveKit Server SDK for Elixir

This is *not* official Elixir server SDK for [LiveKit](https://livekit.io). This SDK allows you to manage rooms and create access tokens from your Elixir backend.

## Installation

Add `livekit` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:livekit, "~> 0.1.0"}
  ]
end
```

## Usage

### Command Line Interface (CLI)

The SDK includes a CLI for common LiveKit operations:

```bash
# Room Management
mix livekit create-token --api-key devkey --api-secret secret --join --room my-room --identity user1 --valid-for 24h
mix livekit list-rooms --api-key devkey --api-secret secret --url https://my.livekit.server
mix livekit create-room --api-key devkey --api-secret secret --url https://my.livekit.server --name my-room
mix livekit delete-room --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room
mix livekit list-participants --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room
mix livekit remove-participant --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --identity user1

# Egress Operations
mix livekit start-room-recording --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --output s3://bucket/recording.mp4
mix livekit start-track-recording --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --track-id TR_1234 --output recordings/track.mp4
mix livekit start-room-stream --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --rtmp rtmp://stream.url/live
mix livekit start-track-stream --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --track-id TR_1234 --rtmp rtmp://stream.url/live
mix livekit list-egress --api-key devkey --api-secret secret --url https://my.livekit.server
mix livekit stop-egress --api-key devkey --api-secret secret --url https://my.livekit.server --egress-id EG_1234

# Room Agents
mix livekit add-agent --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --name assistant --prompt "You are a helpful assistant"
mix livekit remove-agent --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --name assistant
mix livekit list-agents --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room
```

Common options:
- `--api-key` (`-k`): LiveKit API key
- `--api-secret` (`-s`): LiveKit API secret
- `--url` (`-u`): LiveKit server URL
- `--room` (`-r`): Room name
- `--identity` (`-i`): Participant identity
- `--valid-for` (`-t`): Token validity duration (e.g., "24h", "30m")
- `--name` (`-n`): Name for new room or agent

Egress options:
- `--output` (`-o`): Output path (local file or s3://bucket/path)
- `--rtmp`: RTMP streaming URL
- `--width`: Video width (default: 1280)
- `--height`: Video height (default: 720)
- `--fps`: Frames per second (default: 30)
- `--audio-bitrate`: Audio bitrate in bps (default: 128000)
- `--video-bitrate`: Video bitrate in bps (default: 3000000)
- `--track-id`: Track ID for track-specific operations
- `--egress-id`: Egress ID for stopping operations

For more information about available commands and options:
```bash
mix help livekit
```

### Creating Access Tokens

```elixir
alias LiveKit.AccessToken
alias LiveKit.Grants

# Create a new access token
token = AccessToken.new("api-key", "api-secret")
  |> AccessToken.with_identity("user-id")
  |> AccessToken.with_ttl(3600) # 1 hour
  |> AccessToken.add_grant(Grants.join_room("room-name"))

# Convert to JWT
jwt = AccessToken.to_jwt(token)
```

### Managing Rooms

```elixir
alias LiveKit.RoomServiceClient

# Create a client
client = RoomServiceClient.new("https://your-livekit-host", "api-key", "api-secret")

# Create a room
{:ok, room} = RoomServiceClient.create_room(client, "room-name", empty_timeout: 300)

# List rooms
{:ok, rooms} = RoomServiceClient.list_rooms(client)

# Delete a room
{:ok, _} = RoomServiceClient.delete_room(client, "room-name")

# Update room metadata
{:ok, room} = RoomServiceClient.update_room_metadata(client, "room-name", "new metadata")

# List participants in a room
{:ok, participants} = RoomServiceClient.list_participants(client, "room-name")

# Get a specific participant
{:ok, participant} = RoomServiceClient.get_participant(client, "room-name", "participant-identity")

# Remove a participant from a room
{:ok, _} = RoomServiceClient.remove_participant(client, "room-name", "participant-identity")

# Mute/unmute a participant's track
{:ok, track} = RoomServiceClient.mute_published_track(client, "room-name", "participant-identity", "track-sid", true)

# Update participant information
{:ok, participant} = RoomServiceClient.update_participant(client, "room-name", "participant-identity",
  metadata: "new metadata",
  permission: %LiveKit.ParticipantPermission{
    can_publish: true,
    can_subscribe: true,
    can_publish_data: true
  }
)

# Update participant subscriptions
{:ok, _} = RoomServiceClient.update_subscriptions(client, "room-name", "participant-identity",
  track_sids: ["track-1", "track-2"],
  subscribe: true
)

# Send data to participants
{:ok, _} = RoomServiceClient.send_data(client, "room-name", "Hello, participants!",
  kind: :RELIABLE,
  destination_identities: ["participant-1", "participant-2"]
)
```

### Verifying Tokens

```elixir
alias LiveKit.TokenVerifier

# Verify a token
case TokenVerifier.verify(jwt, "api-secret") do
  {:ok, claims} ->
    # Token is valid, claims contains the decoded data
    IO.inspect(claims)
  {:error, reason} ->
    # Token is invalid
    IO.puts("Invalid token: #{inspect(reason)}")
end
```

### Room Egress

```elixir
# Configure automatic room recording
{:ok, room} = RoomServiceClient.create_room(client, "room-name",
  egress: %LiveKit.RoomEgress{
    room: %LiveKit.RoomCompositeEgressRequest{
      file: %LiveKit.EncodedFileOutput{
        filepath: "recordings/room-name.mp4",
        disable_manifest: false
      },
      options: %LiveKit.RoomCompositeEgressRequest.Options{
        video_width: 1280,
        video_height: 720,
        fps: 30,
        audio_bitrate: 128000,
        video_bitrate: 3000000
      }
    }
  }
)
```

### Room Agents

```elixir
# Configure room agents
{:ok, room} = RoomServiceClient.create_room(client, "room-name",
  agents: [
    %LiveKit.RoomAgentDispatch{
      name: "my-agent",
      identity: "agent-1",
      init_request: %{
        "prompt" => "You are a helpful assistant"
      }
    }
  ]
)
```

### Development

#### Protobuf Compilation

The SDK includes a Mix task for compiling protobuf definitions:

```bash
mix compile.proto
```

This will compile all `.proto` files in the `proto/` directory and generate Elixir modules in `lib/livekit/proto/`.

## License

Apache License 2.0

# Livekit Server SDK for Elixir

**⚠️ IMPORTANT DISCLAIMER: This is an early development version (v0.1.1) and is NOT intended for production use. The codebase is in active development, APIs may change without notice, and thorough testing in a production environment has not been conducted. Use at your own risk for development and testing purposes only. We strongly recommend waiting for a stable release before using this in any production environment.**

This is *not* official Elixir server SDK for [Livekit](https://livekit.io). This SDK allows you to manage rooms and create access tokens from your Elixir backend.

## Feature Support

The following table shows which LiveKit features are currently supported in this Elixir SDK:

### Core Features

- [x] Access Token Generation and Management
- [x] Room Management (create, list, delete)
- [x] Participant Management (list, remove)
- [x] Token Verification
- [x] Configuration via Environment Variables
- [x] Configuration via Application Config
- [x] Runtime Configuration Options

### Media Features

- [x] Room Composite Egress (recording rooms)
- [x] Track Composite Egress (recording specific tracks)
- [x] Room Streaming to RTMP
- [x] Track Streaming to RTMP
- [x] Custom Encoding Options for Egress
- [ ] WebRTC Ingress
- [ ] RTMP Ingress
- [ ] WHIP Ingress

### AI Features

- [x] Room Agents (add, remove, list)
- [x] Agent Configuration and Initialization

### Integration Features

- [ ] SIP Inbound Trunks
- [ ] SIP Outbound Trunks
- [ ] SIP Call Management
- [ ] Webhook Support and Validation
- [ ] Webhook Event Processing

### Advanced Features

- [ ] Advanced Room Configuration
- [ ] Room Presets
- [ ] Detailed Codec Configuration
- [ ] Advanced Participant Permissions
- [ ] Data Message Handling with Reliability Options
- [ ] Additional Grant Types (SIPGrant, etc.)

## Installation

Add `livekit` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:livekit, "~> 0.1"}
  ]
end
```

## Usage

### Command Line Interface (CLI)

The SDK includes a CLI for common Livekit operations. Here are all available commands grouped by category:

#### Room Management

```bash
# Create an access token for room access
mix livekit create-token --api-key devkey --api-secret secret --url http://localhost:7880 --join --room my-room --identity user1 --valid-for 24h --identity user1 --valid-for 24h

# List all rooms
mix livekit list-rooms --api-key devkey --api-secret secret --url http://localhost:7880

# Create a new room
mix livekit create-room --api-key devkey --api-secret secret --url http://localhost:7880 --name my-room

# Delete a room
mix livekit delete-room --api-key devkey --api-secret secret --url http://localhost:7880 --room my-room

# List participants in a room
mix livekit list-participants --api-key devkey --api-secret secret --url http://localhost:7880 --room my-room

# Remove a participant from a room
mix livekit remove-participant --api-key devkey --api-secret secret --url http://localhost:7880 --room my-room --identity user1
```

#### Recording and Streaming

```bash
# Start recording a room
mix livekit start-room-recording --api-key devkey --api-secret secret --url http://localhost:7880 --room my-room --output s3://bucket/recording.mp4

# Start recording specific tracks
mix livekit start-track-recording --api-key devkey --api-secret secret --url http://localhost:7880 --room my-room --track-id TR_1234 --output recordings/track.mp4

# Start streaming a room to RTMP endpoints
mix livekit start-room-streaming --api-key devkey --api-secret secret --url http://localhost:7880 --room my-room --rtmp rtmp://stream.url/live

# Start streaming specific tracks to RTMP endpoints
mix livekit start-track-stream --api-key devkey --api-secret secret --url http://localhost:7880 --room my-room --track-id TR_1234 --rtmp rtmp://stream.url/live

# List active egress operations
mix livekit list-egress --api-key devkey --api-secret secret --url http://localhost:7880

# Stop an egress operation
mix livekit stop-egress --api-key devkey --api-secret secret --url http://localhost:7880 --egress-id EG_1234
```

#### Room Agents

```bash
# Add an agent to a room
mix livekit add-agent --api-key devkey --api-secret secret --url http://localhost:7880 --room my-room --name assistant --prompt "You are a helpful assistant"

# Remove an agent from a room
mix livekit remove-agent --api-key devkey --api-secret secret --url http://localhost:7880 --room my-room --name assistant

# List agents in a room
mix livekit list-agents --api-key devkey --api-secret secret --url http://localhost:7880 --room my-room
```

### Command Options

#### Common Options

- `--api-key` (`-k`): Livekit API key (required)
- `--api-secret` (`-s`): Livekit API secret (required)
- `--url` (`-u`): Livekit server URL (required for most commands)
- `--room` (`-r`): Room name
- `--identity` (`-i`): Participant identity
- `--name` (`-n`): Name for new room or agent
- `--valid-for` (`-t`): Token validity duration (e.g., "24h", "30m")

#### Recording and Streaming Options

- `--output` (`-o`): Output path (local file or s3://bucket/path)
- `--rtmp`: RTMP streaming URL
- `--width`: Video width (default: 1280)
- `--height`: Video height (default: 720)
- `--fps`: Frames per second (default: 30)
- `--audio-bitrate`: Audio bitrate in bps (default: 128000)
- `--video-bitrate`: Video bitrate in bps (default: 3000000)
- `--track-id`: Track ID for track-specific operations
- `--egress-id`: Egress ID for stopping operations

#### Agent Options

- `--prompt`: Initial prompt for the agent (required for add-agent)
- `--name`: Agent name (required for add/remove agent)

For more detailed information about available commands and options:

```bash
mix help livekit
```

## Code Examples

### Creating Access Tokens

```elixir
# Create a new access token
token = Livekit.AccessToken.new("devkey", "secret")
  |> Livekit.AccessToken.with_identity("user-id")
  |> Livekit.AccessToken.with_ttl(3600) # 1 hour
  |> Livekit.AccessToken.add_grant(Livekit.Grants.join_room("room-name"))

# Convert to JWT
jwt = Livekit.AccessToken.to_jwt(token)
```

### Managing Rooms

```elixir
# Create a client
client = Livekit.RoomServiceClient.new("http://localhost:7880", "devkey", "secret")

# Create a room
{:ok, room} = Livekit.RoomServiceClient.create_room(client, "room-name", empty_timeout: 300)

# List rooms
{:ok, rooms} = Livekit.RoomServiceClient.list_rooms(client)

# Delete a room
{:ok, _} = Livekit.RoomServiceClient.delete_room(client, "room-name")

# List participants in a room
{:ok, participants} = Livekit.RoomServiceClient.list_participants(client, "room-name")

# Remove a participant from a room
{:ok, _} = Livekit.RoomServiceClient.remove_participant(client, "room-name", "participant-identity")
```

### Verifying Tokens

```elixir
# Verify a token
case Livekit.TokenVerifier.verify(jwt, "secret") do
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
{:ok, room} = Livekit.RoomServiceClient.create_room(client, "room-name",
  egress: %Livekit.RoomEgress{
    room: %Livekit.RoomCompositeEgressRequest{
      file_outputs: [
        %Livekit.EncodedFileOutput{
          filepath: "recordings/room-name.mp4",
          disable_manifest: false
        }
      ],
      encoding_options: %Livekit.RoomCompositeEgressRequest.Options{
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
{:ok, room} = Livekit.RoomServiceClient.create_room(client, "room-with-agents",
  agents: [
    %Livekit.RoomAgentDispatch{
      name: "my-agent",
      identity: "agent-1",
      init_request: %{
        "prompt" => "You are a helpful assistant"
      }
    }
  ]
)
```

## Configuration

The SDK supports multiple ways to configure Livekit credentials and settings:

### Environment Variables

You can set your Livekit configuration using environment variables:

```bash
export LIVEKIT_URL="wss://your-livekit-server.com"
export LIVEKIT_API_KEY="your-api-key"
export LIVEKIT_API_SECRET="your-api-secret"
```

### Application Configuration

Add Livekit configuration to your `config/config.exs` or environment-specific config file:

```elixir
config :livekit,
  url: "wss://your-livekit-server.com",
  api_key: "your-api-key",
  api_secret: "your-api-secret"
```

### Runtime Configuration

You can override configuration at runtime by passing options to functions:

```elixir
opts = [
  url: "wss://different-server.com",
  api_key: "different-key",
  api_secret: "different-secret"
]

# These options will override any environment or application config
mix livekit create-token --room my-room --identity user1 --valid-for 24h
```

The configuration system follows this priority order:

1. Runtime options (highest priority)
2. Environment variables
3. Application configuration
4. Default values (lowest priority)

## Development

### Protobuf Compilation

The SDK includes a Mix task for compiling protobuf definitions:

```bash
mix compile.proto
```

This will compile all `.proto` files in the `proto/` directory and generate Elixir modules in `lib/livekit/proto/`.

## Future Development Roadmap

The features marked as not implemented in the feature checklist are planned for future releases of the Elixir SDK. If you need these features immediately, consider using one of the other official SDKs.

Contributions to implement these features are welcome! Please see the repository for contribution guidelines.

## License

Apache License 2.0

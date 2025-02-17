# Livekit Server SDK for Elixir

**⚠️ IMPORTANT DISCLAIMER: This is an early development version (v0.1.1) and is NOT intended for production use. The codebase is in active development, APIs may change without notice, and thorough testing in a production environment has not been conducted. Use at your own risk for development and testing purposes only. We strongly recommend waiting for a stable release before using this in any production environment.**

This is *not* official Elixir server SDK for [Livekit](https://livekit.io). This SDK allows you to manage rooms and create access tokens from your Elixir backend.

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
mix livekit create-token --api-key devkey --api-secret secret --join --room my-room --identity user1 --valid-for 24h

# List all rooms
mix livekit list-rooms --api-key devkey --api-secret secret --url https://my.livekit.server

# Create a new room
mix livekit create-room --api-key devkey --api-secret secret --url https://my.livekit.server --name my-room

# Delete a room
mix livekit delete-room --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room

# List participants in a room
mix livekit list-participants --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room

# Remove a participant from a room
mix livekit remove-participant --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --identity user1
```

#### Recording and Streaming
```bash
# Start recording a room
mix livekit start-room-recording --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --output s3://bucket/recording.mp4

# Start recording specific tracks
mix livekit start-track-recording --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --track-id TR_1234 --output recordings/track.mp4

# Start streaming a room to RTMP endpoints
mix livekit start-room-streaming --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --rtmp rtmp://stream.url/live

# Start streaming specific tracks to RTMP endpoints
mix livekit start-track-stream --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --track-id TR_1234 --rtmp rtmp://stream.url/live

# List active egress operations
mix livekit list-egress --api-key devkey --api-secret secret --url https://my.livekit.server

# Stop an egress operation
mix livekit stop-egress --api-key devkey --api-secret secret --url https://my.livekit.server --egress-id EG_1234
```

#### Room Agents
```bash
# Add an agent to a room
mix livekit add-agent --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --name assistant --prompt "You are a helpful assistant"

# Remove an agent from a room
mix livekit remove-agent --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --name assistant

# List agents in a room
mix livekit list-agents --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room
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

### Creating Access Tokens

```elixir
alias Livekit.AccessToken
alias Livekit.Grants

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
alias Livekit.RoomServiceClient

# Create a client
client = RoomServiceClient.new("https://your-livekit-host", "api-key", "api-secret")

# Create a room
{:ok, room} = RoomServiceClient.create_room(client, "room-name", empty_timeout: 300)

# List rooms
{:ok, rooms} = RoomServiceClient.list_rooms(client)

# Delete a room
{:ok, _} = RoomServiceClient.delete_room(client, "room-name")

# List participants in a room
{:ok, participants} = RoomServiceClient.list_participants(client, "room-name")

# Remove a participant from a room
{:ok, _} = RoomServiceClient.remove_participant(client, "room-name", "participant-identity")
```

### Verifying Tokens

```elixir
alias Livekit.TokenVerifier

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
  egress: %Livekit.RoomEgress{
    room: %Livekit.RoomCompositeEgressRequest{
      file: %Livekit.EncodedFileOutput{
        filepath: "recordings/room-name.mp4",
        disable_manifest: false
      },
      options: %Livekit.RoomCompositeEgressRequest.Options{
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

### Configuration

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

### Development

#### Protobuf Compilation

The SDK includes a Mix task for compiling protobuf definitions:

```bash
mix compile.proto
```

This will compile all `.proto` files in the `proto/` directory and generate Elixir modules in `lib/livekit/proto/`.

## License

Apache License 2.0

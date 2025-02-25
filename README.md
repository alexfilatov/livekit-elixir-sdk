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
- [x] Webhook Support and Validation
- [x] Webhook Event Processing

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

#### Webhook Options

- `--payload`: Webhook payload to verify
- `--token`: Webhook token to verify with
- `--webhook-url`: Webhook URL to generate configuration for

#### Webhook Commands

```bash
# Generate webhook configuration
mix livekit generate-webhook-config --api-key devkey --api-secret secret --webhook-url https://your-webhook-endpoint.com/webhooks

# Verify a webhook payload
mix livekit verify-webhook --api-key devkey --api-secret secret --payload '{"event": "room_created", "room": {"name": "test-room"}}' --token "your-webhook-token"

# Configure webhooks in the server (see [official docs](https://docs.livekit.io/home/server/webhooks/))
# Add this to your livekit server configuration file:
webhook:
  # The API key to use for signing webhook messages
  api_key: 'your_livekit_api_key'
  urls:
    - 'https://your-app-domain.com/api/webhooks/livekit'
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

### Webhooks

The SDK provides support for receiving and validating webhook events from LiveKit:

```elixir
# In a Phoenix controller
def webhook(conn, _params) do
  with {:ok, body, conn} <- Plug.Conn.read_body(conn),
       auth_header = Plug.Conn.get_req_header(conn, "authorization"),
       {:ok, event} <- Livekit.WebhookReceiver.receive(body, auth_header) do
    
    # Handle the webhook event
    case event.event do
      "room_started" -> handle_room_started(event)
      "participant_joined" -> handle_participant_joined(event)
      # ... handle other events
    end
    
    send_resp(conn, 200, "")
  else
    {:error, reason} ->
      conn
      |> put_status(400)
      |> json(%{error: reason})
  end
end

# Example event handlers
defp handle_room_started(event) do
  IO.puts("Room started: #{event.room.name}")
end

defp handle_participant_joined(event) do
  IO.puts("Participant joined: #{event.participant.identity} in room #{event.room.name}")
end
```

## Webhooks

LiveKit can send webhook events to your application when certain events occur. This SDK provides a `WebhookReceiver` module to help you validate and process these webhook events.

### Configuration

Add the following to your `config.exs` file:

```elixir
config :livekit, :webhook,
  api_key: "your_api_key",
  api_secret: "your_api_secret",
  urls: ["https://your-webhook-endpoint.com/webhook"]
```

### Receiving Webhooks

To receive and validate webhook events in your Phoenix application:

```elixir
defmodule YourApp.WebhookController do
  use YourApp, :controller

  def handle(conn, _params) do
    with {:ok, body, conn} <- read_body(conn),
         auth_header = get_req_header(conn, "authorization") |> List.first(),
         {:ok, event} <- Livekit.WebhookReceiver.receive(body, auth_header) do
      
      # Handle the webhook event based on its type
      case event.event do
        "room_created" ->
          # Handle room creation event
          IO.puts("Room created: #{event.room.name} (#{event.room.sid})")
          
        "participant_joined" ->
          # Handle participant joined event
          IO.puts("Participant joined: #{event.participant.identity}")
          
        "track_published" ->
          # Handle track published event
          IO.puts("Track published: #{event.track.name}")
          
        _ ->
          # Handle other event types
          IO.puts("Received event: #{event.event}")
      end
      
      conn
      |> put_status(200)
      |> json(%{success: true})
    else
      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{error: "Invalid webhook: #{inspect(reason)}"})
    end
  end
end
```

### Webhook Event Types

LiveKit can send the following webhook event types:

- Room events: `room_created`, `room_updated`, `room_deleted`, `room_started`, `room_finished`
- Participant events: `participant_joined`, `participant_left`, `participant_active`, `participant_inactive`
- Track events: `track_published`, `track_unpublished`, `track_subscribed`, `track_unsubscribed`, `track_muted`, `track_unmuted`
- Egress events: `egress_started`, `egress_updated`, `egress_ended`, `egress_failed`
- Ingress events: `ingress_started`, `ingress_ended`, `ingress_failed`

### Phoenix Integration

Here's a complete example of integrating LiveKit webhooks in a Phoenix application:

#### Step 1: Configure Your LiveKit Webhook Settings

Add the webhook configuration to your `config/config.exs` file:

```elixir
config :livekit, :webhook,
  api_key: "your_livekit_api_key",
  api_secret: "your_livekit_api_secret"
```

#### Step 2: Create a Webhook Controller

Create a dedicated controller to handle incoming webhook events:

```elixir
# lib/your_app_web/controllers/webhook_controller.ex
defmodule YourAppWeb.WebhookController do
  use YourAppWeb, :controller
  require Logger

  def handle(conn, _params) do
    with {:ok, body, conn} <- read_body(conn),
         auth_header = get_req_header(conn, "authorization") |> List.first(),
         {:ok, event} <- Livekit.WebhookReceiver.receive(body, auth_header) do
      
      # Process the webhook event
      process_webhook_event(event)
      
      # Return a success response
      conn
      |> put_status(200)
      |> json(%{success: true})
    else
      {:error, reason} ->
        Logger.error("Webhook validation failed: #{inspect(reason)}")
        
        conn
        |> put_status(400)
        |> json(%{error: "Invalid webhook request"})
    end
  end
  
  defp process_webhook_event(event) do
    Logger.info("Received webhook event: #{event.event}")
    
    case event.event do
      "room_created" ->
        handle_room_created(event.room)
        
      "participant_joined" ->
        handle_participant_joined(event.participant, event.room)
        
      "track_published" ->
        handle_track_published(event.track, event.participant, event.room)
        
      # Add more event handlers as needed
      _ ->
        Logger.info("Unhandled event type: #{event.event}")
    end
  end
  
  defp handle_room_created(room) do
    Logger.info("Room created: #{room.name} (#{room.sid})")
    # Your custom logic for room creation
  end
  
  defp handle_participant_joined(participant, room) do
    Logger.info("Participant #{participant.identity} joined room #{room.name}")
    # Your custom logic for participant joining
  end
  
  defp handle_track_published(track, participant, room) do
    Logger.info("Track #{track.sid} published by #{participant.identity} in room #{room.name}")
    # Your custom logic for track publishing
  end
end
```

#### Step 3: Add the Route

Add a route for your webhook controller in your router file:

```elixir
# lib/your_app_web/router.ex
defmodule YourAppWeb.Router do
  use YourAppWeb, :router
  
  # ... other router code ...
  
  scope "/api", YourAppWeb do
    pipe_through :api
    
    post "/webhooks/livekit", WebhookController, :handle
  end
end
```

#### Step 4: Configure LiveKit to Send Webhooks

In your LiveKit server configuration, set up the webhook URL to point to your Phoenix endpoint:

```yaml
# livekit.yaml or equivalent configuration
webhook:
  # The API key to use for signing webhook messages
  api_key: 'your_livekit_api_key'
  urls:
    - 'https://your-app-domain.com/api/webhooks/livekit'
```

For more information, see the [official LiveKit webhook documentation](https://docs.livekit.io/home/server/webhooks/).

Make sure your LiveKit server is properly configured to send webhooks to your application endpoint.

#### Best Practices

1. **Validate All Webhooks**: Always use the `WebhookReceiver.receive/2` function to validate incoming webhooks.
2. **Idempotent Handlers**: Make your event handlers idempotent to handle potential duplicate events.
3. **Async Processing**: For time-consuming operations, consider using Elixir's async capabilities or a job queue.
4. **Logging**: Implement comprehensive logging for debugging and monitoring.
5. **Error Handling**: Properly handle and report errors to avoid silent failures.

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

config :livekit, :webhook,
  api_key: "your-api-key",
  api_secret: "your-api-secret",
  urls: ["https://your-webhook-endpoint.com/webhook"]
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

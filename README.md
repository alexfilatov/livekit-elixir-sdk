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

## License

Apache License 2.0

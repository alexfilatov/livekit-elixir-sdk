Mix.install(
  [
    {:livekit, path: "../", compile: true},
    {:jason, "~> 1.4"}
  ],
  force: true
)

# Advanced example of using Livekit SDK with error handling and retries
#
# To run this example:
# 1. Set your Livekit server URL, API key, and API secret
# 2. Run with: `elixir advanced_room_management.exs`

alias Livekit.{AccessToken, RoomServiceClient, Grants}

# Replace these with your Livekit server credentials
server_url = "ws://localhost:7880"
api_key = "devkey"
api_secret = "secret"

defmodule RoomManager do
  @max_retries 3
  @retry_delay 1000 # 1 second

  def with_retries(fun) do
    do_with_retries(fun, 0)
  end

  defp do_with_retries(fun, retry_count) when retry_count < @max_retries do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, :request_failed} ->
        IO.puts("Request failed, retrying in #{@retry_delay}ms (attempt #{retry_count + 1}/#{@max_retries})")
        Process.sleep(@retry_delay)
        do_with_retries(fun, retry_count + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_with_retries(_fun, _retry_count) do
    {:error, :max_retries_exceeded}
  end

  def create_room_with_token(client, room_name, opts \\ []) do
    # First try to create the room
    case with_retries(fn -> RoomServiceClient.create_room(client, room_name, opts) end) do
      {:ok, room} ->
        # Generate an admin token for the room
        token = generate_admin_token(client, room_name)
        {:ok, %{room: room, token: token}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def generate_admin_token(client, room_name) do
    AccessToken.new(client.api_key, client.api_secret)
    |> AccessToken.with_identity("admin-#{:rand.uniform(1000)}")
    |> AccessToken.with_ttl(3600)
    |> AccessToken.add_grant(%{
      room_join: true,
      room: room_name,
      can_publish: true,
      can_subscribe: true,
      can_publish_data: true,
      can_admin: true
    })
    |> AccessToken.to_jwt()
  end

  def ensure_room_exists(client, room_name, opts \\ []) do
    case with_retries(fn -> RoomServiceClient.list_rooms(client) end) do
      {:ok, %{"rooms" => rooms}} ->
        if Enum.any?(rooms, & &1["name"] == room_name) do
          {:ok, :room_exists}
        else
          create_room_with_token(client, room_name, opts)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def cleanup_empty_rooms(client) do
    case with_retries(fn -> RoomServiceClient.list_rooms(client) end) do
      {:ok, %{"rooms" => rooms}} ->
        empty_rooms = Enum.filter(rooms, & &1["num_participants"] == 0)

        results = Enum.map(empty_rooms, fn room ->
          case with_retries(fn -> RoomServiceClient.delete_room(client, room["name"]) end) do
            {:ok, _} -> {:ok, room["name"]}
            {:error, reason} -> {:error, {room["name"], reason}}
          end
        end)

        {
          Enum.filter(results, fn {status, _} -> status == :ok end),
          Enum.filter(results, fn {status, _} -> status == :error end)
        }

      {:error, reason} ->
        {:error, reason}
    end
  end
end

# Initialize the client
client = RoomServiceClient.new(server_url, api_key, api_secret)

# Example usage
IO.puts("\n=== Creating a room with admin token ===")
room_name = "advanced-room-#{:rand.uniform(1000)}"
case RoomManager.create_room_with_token(client, room_name) do
  {:ok, %{room: room, token: token}} ->
    IO.puts("Room created successfully:")
    IO.inspect(room, pretty: true)
    IO.puts("\nAdmin token generated:")
    IO.puts(token)

  {:error, reason} ->
    IO.puts("Failed to create room: #{inspect(reason)}")
end

IO.puts("\n=== Ensuring room exists ===")
case RoomManager.ensure_room_exists(client, "persistent-room") do
  {:ok, :room_exists} ->
    IO.puts("Room already exists")

  {:ok, %{room: room, token: token}} ->
    IO.puts("Room created:")
    IO.inspect(room, pretty: true)
    IO.puts("\nAdmin token:")
    IO.puts(token)

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

IO.puts("\n=== Cleaning up empty rooms ===")
case RoomManager.cleanup_empty_rooms(client) do
  {successful, failed} ->
    IO.puts("\nSuccessfully deleted rooms:")
    Enum.each(successful, fn {:ok, name} -> IO.puts("- #{name}") end)

    unless Enum.empty?(failed) do
      IO.puts("\nFailed to delete rooms:")
      Enum.each(failed, fn {:error, {name, reason}} ->
        IO.puts("- #{name}: #{inspect(reason)}")
      end)
    end

  {:error, reason} ->
    IO.puts("Failed to cleanup rooms: #{inspect(reason)}")
end

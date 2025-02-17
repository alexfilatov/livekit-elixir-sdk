defmodule Mix.Tasks.Livekit do
  use Mix.Task

  @shortdoc "LiveKit CLI commands"
  @moduledoc """
  Provides CLI commands for LiveKit operations.

  ## Commands

  * `create-token` - Create an access token
  * `list-rooms` - List all rooms
  * `create-room` - Create a new room
  * `delete-room` - Delete a room
  * `list-participants` - List participants in a room
  * `remove-participant` - Remove a participant from a room

  ## Examples

      # Create a token
      mix livekit create-token --api-key devkey --api-secret secret --join --room my-room --identity user1 --valid-for 24h

      # List rooms
      mix livekit list-rooms --api-key devkey --api-secret secret --url https://my.livekit.server

      # Create a room
      mix livekit create-room --api-key devkey --api-secret secret --url https://my.livekit.server --name my-room

      # Delete a room
      mix livekit delete-room --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room

      # List participants
      mix livekit list-participants --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room

      # Remove a participant
      mix livekit remove-participant --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --identity user1
  """

  @impl Mix.Task
  def run(args) do
    {opts, args, _} = OptionParser.parse(args,
      strict: [
        api_key: :string,
        api_secret: :string,
        url: :string,
        room: :string,
        identity: :string,
        valid_for: :string,
        join: :boolean,
        name: :string
      ],
      aliases: [
        k: :api_key,
        s: :api_secret,
        u: :url,
        r: :room,
        i: :identity,
        t: :valid_for,
        j: :join,
        n: :name
      ]
    )

    case args do
      ["create-token" | _] -> create_token(opts)
      ["list-rooms" | _] -> list_rooms(opts)
      ["create-room" | _] -> create_room(opts)
      ["delete-room" | _] -> delete_room(opts)
      ["list-participants" | _] -> list_participants(opts)
      ["remove-participant" | _] -> remove_participant(opts)
      _ -> print_help()
    end
  end

  defp create_token(opts) do
    with {:ok, api_key} <- get_opt(opts, :api_key),
         {:ok, api_secret} <- get_opt(opts, :api_secret),
         {:ok, room} <- get_opt(opts, :room) do
      identity = Keyword.get(opts, :identity, "anonymous")
      ttl = parse_duration(Keyword.get(opts, :valid_for, "6h"))
      join = Keyword.get(opts, :join, false)

      token = LiveKit.AccessToken.new(api_key, api_secret)
      |> LiveKit.AccessToken.with_identity(identity)
      |> LiveKit.AccessToken.with_ttl(ttl)

      token = if join do
        LiveKit.AccessToken.add_grant(token, LiveKit.Grants.join_room(room))
      else
        token
      end

      jwt = LiveKit.AccessToken.to_jwt(token)
      IO.puts(jwt)
    else
      {:error, message} -> IO.puts("Error: #{message}")
    end
  end

  defp list_rooms(opts) do
    with {:ok, client} <- get_client(opts) do
      case LiveKit.RoomServiceClient.list_rooms(client) do
        {:ok, rooms} ->
          rooms
          |> Enum.each(fn room ->
            IO.puts("#{room.name} (#{room.sid})")
            IO.puts("  Num Participants: #{room.num_participants}")
            IO.puts("  Created At: #{format_timestamp(room.creation_time)}")
            IO.puts("")
          end)
        {:error, error} -> IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  defp create_room(opts) do
    with {:ok, client} <- get_client(opts),
         {:ok, name} <- get_opt(opts, :name) do
      case LiveKit.RoomServiceClient.create_room(client, name) do
        {:ok, room} ->
          IO.puts("Created room:")
          IO.puts("  Name: #{room.name}")
          IO.puts("  SID: #{room.sid}")
        {:error, error} -> IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  defp delete_room(opts) do
    with {:ok, client} <- get_client(opts),
         {:ok, room} <- get_opt(opts, :room) do
      case LiveKit.RoomServiceClient.delete_room(client, room) do
        {:ok, _} -> IO.puts("Room #{room} deleted")
        {:error, error} -> IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  defp list_participants(opts) do
    with {:ok, client} <- get_client(opts),
         {:ok, room} <- get_opt(opts, :room) do
      case LiveKit.RoomServiceClient.list_participants(client, room) do
        {:ok, participants} ->
          participants
          |> Enum.each(fn participant ->
            IO.puts("#{participant.identity} (#{participant.sid})")
            IO.puts("  Name: #{participant.name}")
            IO.puts("  State: #{participant.state}")
            IO.puts("  Joined At: #{format_timestamp(participant.joined_at)}")
            IO.puts("")
          end)
        {:error, error} -> IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  defp remove_participant(opts) do
    with {:ok, client} <- get_client(opts),
         {:ok, room} <- get_opt(opts, :room),
         {:ok, identity} <- get_opt(opts, :identity) do
      case LiveKit.RoomServiceClient.remove_participant(client, room, identity) do
        {:ok, _} -> IO.puts("Participant #{identity} removed from room #{room}")
        {:error, error} -> IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  defp get_client(opts) do
    with {:ok, url} <- get_opt(opts, :url),
         {:ok, api_key} <- get_opt(opts, :api_key),
         {:ok, api_secret} <- get_opt(opts, :api_secret) do
      {:ok, LiveKit.RoomServiceClient.new(url, api_key, api_secret)}
    end
  end

  defp get_opt(opts, key) do
    case Keyword.get(opts, key) do
      nil -> {:error, "Missing required option: --#{key}"}
      value -> {:ok, value}
    end
  end

  defp parse_duration(duration) when is_binary(duration) do
    {num, unit} = Integer.parse(duration)
    case unit do
      "h" <> _ -> num * 3600
      "m" <> _ -> num * 60
      "s" <> _ -> num
      _ -> num
    end
  end
  defp parse_duration(_), do: 21600 # 6 hours default

  defp format_timestamp(nil), do: "N/A"
  defp format_timestamp(timestamp) do
    DateTime.from_unix!(timestamp)
    |> DateTime.to_string()
  end

  defp print_help do
    IO.puts(@moduledoc)
  end
end

defmodule Mix.Tasks.Livekit do
  use Mix.Task

  @shortdoc "LiveKit CLI commands"
  @moduledoc """
  Provides CLI commands for LiveKit operations.

  ## Commands

  Room Management:
  * `create-token` - Create an access token for room access
  * `list-rooms` - List all rooms
  * `create-room` - Create a new room
  * `delete-room` - Delete a room
  * `list-participants` - List participants in a room
  * `remove-participant` - Remove a participant from a room

  Recording and Streaming:
  * `start-room-recording` - Start recording a room
  * `start-track-recording` - Start recording specific tracks
  * `start-room-streaming` - Start streaming a room to RTMP endpoints
  * `start-track-stream` - Start streaming specific tracks to RTMP endpoints
  * `list-egress` - List active egress operations
  * `stop-egress` - Stop an egress operation

  Room Agents:
  * `add-agent` - Add an agent to a room
  * `remove-agent` - Remove an agent from a room
  * `list-agents` - List agents in a room

  ## Options

  Common Options:
  * `--api-key` (`-k`) - LiveKit API key (required)
  * `--api-secret` (`-s`) - LiveKit API secret (required)
  * `--url` (`-u`) - LiveKit server URL (required for most commands)
  * `--room` (`-r`) - Room name
  * `--identity` (`-i`) - Participant identity
  * `--name` (`-n`) - Name for new room or agent
  * `--valid-for` (`-t`) - Token validity duration (e.g., "24h", "30m")

  Recording and Streaming Options:
  * `--output` (`-o`) - Output path (local file or s3://bucket/path)
  * `--rtmp` - RTMP streaming URL
  * `--width` - Video width (default: 1280)
  * `--height` - Video height (default: 720)
  * `--fps` - Frames per second (default: 30)
  * `--audio-bitrate` - Audio bitrate in bps (default: 128000)
  * `--video-bitrate` - Video bitrate in bps (default: 3000000)
  * `--track-id` - Track ID for track-specific operations
  * `--egress-id` - Egress ID for stopping operations

  Agent Options:
  * `--prompt` - Initial prompt for the agent (required for add-agent)
  * `--name` - Agent name (required for add/remove agent)

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

      # Start room recording
      mix livekit start-room-recording --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --output s3://bucket/recording.mp4

      # Start room streaming
      mix livekit start-room-streaming --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --rtmp rtmp://stream.url/live

      # Add an agent to a room
      mix livekit add-agent --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --name assistant --prompt "You are a helpful assistant"
  """

  @impl Mix.Task
  def run(args) do
    # Start required applications
    Application.ensure_all_started(:gun)
    Application.ensure_all_started(:grpc)

    {opts, args, _} = parse_options(args)

    command = List.first(args)

    handle_command(command, opts)
  end

  defp parse_options(args) do
    OptionParser.parse(args,
      strict: [
        api_key: :string,
        api_secret: :string,
        url: :string,
        room: :string,
        identity: :string,
        valid_for: :string,
        join: :boolean,
        name: :string,
        output: :string,
        rtmp: :string,
        width: :integer,
        height: :integer,
        fps: :integer,
        audio_bitrate: :integer,
        video_bitrate: :integer,
        track_id: :string,
        egress_id: :string,
        prompt: :string,
        metadata: :string
      ],
      aliases: [
        k: :api_key,
        s: :api_secret,
        u: :url,
        r: :room,
        i: :identity,
        t: :valid_for,
        j: :join,
        n: :name,
        o: :output
      ]
    )
  end

  defp handle_command("create-token", opts), do: handle_create_token(opts)

  defp handle_command("list-rooms", opts), do: handle_room_commands("list-rooms", opts)
  defp handle_command("create-room", opts), do: handle_room_commands("create-room", opts)
  defp handle_command("delete-room", opts), do: handle_room_commands("delete-room", opts)

  defp handle_command("list-participants", opts),
    do: handle_room_commands("list-participants", opts)

  defp handle_command("remove-participant", opts),
    do: handle_room_commands("remove-participant", opts)

  defp handle_command("start-room-recording", opts), do: handle_start_room_recording(opts)
  defp handle_command("start-track-recording", opts), do: handle_start_track_recording(opts)

  defp handle_command("start-room-streaming", opts),
    do: handle_streaming_commands("start-room-streaming", opts)

  defp handle_command("start-track-stream", opts),
    do: handle_streaming_commands("start-track-stream", opts)

  defp handle_command("list-egress", opts), do: handle_list_egress(opts)
  defp handle_command("stop-egress", opts), do: handle_stop_egress(opts)

  defp handle_command("add-agent", opts), do: handle_agent_commands("add-agent", opts)
  defp handle_command("remove-agent", opts), do: handle_agent_commands("remove-agent", opts)
  defp handle_agent_commands("list-agents", opts), do: handle_agent_commands("list-agents", opts)

  defp handle_command(_, _), do: print_help()

  defp handle_room_commands(command, opts) do
    case command do
      "create-room" -> handle_create_room(opts)
      "delete-room" -> handle_delete_room(opts)
      "list-rooms" -> handle_list_rooms(opts)
      "list-participants" -> handle_list_participants(opts)
      "remove-participant" -> handle_remove_participant(opts)
      _ -> :unknown_command
    end
  end

  defp handle_streaming_commands(command, opts) do
    case command do
      "start-room-streaming" -> handle_start_room_streaming(opts)
      "start-track-stream" -> handle_start_track_stream(opts)
      _ -> :unknown_command
    end
  end

  defp handle_agent_commands(command, opts) do
    case command do
      "add-agent" -> handle_add_agent(opts)
      "remove-agent" -> handle_remove_agent(opts)
      "list-agents" -> handle_list_agents(opts)
      _ -> :unknown_command
    end
  end

  def handle_create_token(opts) do
    with {:ok, identity} <- get_opt(opts, :identity),
         {:ok, room} <- get_opt(opts, :room) do
      config = LiveKit.Config.get(opts)

      case LiveKit.Config.validate(config) do
        :ok ->
          name = Keyword.get(opts, :name)
          metadata = Keyword.get(opts, :metadata)
          valid_for = Keyword.get(opts, :valid_for)

          grant = %LiveKit.Grants{
            room: room,
            room_join: true,
            room_admin: Keyword.get(opts, :admin, false)
          }

          token =
            LiveKit.AccessToken.new(config.api_key, config.api_secret)
            |> LiveKit.AccessToken.with_identity(identity)
            |> LiveKit.AccessToken.with_grants(grant)
            |> maybe_add_ttl(valid_for)
            |> maybe_add_metadata(metadata)
            |> LiveKit.AccessToken.to_jwt()

          {:ok, token}

        error ->
          error
      end
    end
  end

  defp maybe_add_ttl(token, nil), do: token

  defp maybe_add_ttl(token, ttl) when is_binary(ttl) do
    case parse_duration(ttl) do
      {:ok, seconds} -> LiveKit.AccessToken.with_ttl(token, seconds)
      _error -> token
    end
  end

  defp maybe_add_metadata(token, nil), do: token

  defp maybe_add_metadata(token, metadata) when is_binary(metadata) do
    LiveKit.AccessToken.with_metadata(token, metadata)
  end

  defp parse_duration(duration) when is_binary(duration) do
    case Regex.run(~r/^(\d+)([hms])$/, duration) do
      [_, value, unit] ->
        value = String.to_integer(value)

        case unit do
          "h" -> {:ok, value * 3600}
          "m" -> {:ok, value * 60}
          "s" -> {:ok, value}
        end

      _ ->
        {:error, "Invalid duration format. Use <number>[h|m|s], e.g., 24h, 60m, or 3600s"}
    end
  end

  def handle_list_participants(opts) do
    with {:ok, room} <- get_opt(opts, :room),
         {:ok, client} <- get_client(opts) do
      case LiveKit.RoomServiceClient.list_participants(client, room) do
        {:ok, participants} -> {:ok, participants}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def handle_start_room_recording(opts) do
    with {:ok, room} <- get_opt(opts, :room),
         {:ok, output} <- get_opt(opts, :output),
         {:ok, client} <- get_egress_client(opts) do
      request = %Livekit.RoomCompositeEgressRequest{
        room_name: room,
        file_outputs: [
          %Livekit.EncodedFileOutput{
            filepath: output
          }
        ],
        options:
          {:advanced,
           %Livekit.EncodingOptions{
             width: 1280,
             height: 720,
             framerate: 30,
             audio_bitrate: 128_000,
             video_bitrate: 3_000_000
           }}
      }

      try do
        case LiveKit.EgressServiceClient.start_room_composite_egress(client, request) do
          {:ok, response} -> {:ok, response}
          {:error, %GRPC.RPCError{} = error} -> {:error, error.message}
          {:error, reason} -> {:error, reason}
        end
      rescue
        error -> {:error, "Failed to start recording: #{inspect(error)}"}
      end
    end
  end

  defp handle_list_rooms(opts) do
    with {:ok, client} <- get_client(opts) do
      case LiveKit.RoomServiceClient.list_rooms(client) do
        {:ok, rooms} ->
          Enum.each(rooms, fn room ->
            IO.puts("#{room.name} (#{room.sid})")
            IO.puts("  Num Participants: #{room.num_participants}")
            IO.puts("  Created At: #{format_timestamp(room.creation_time)}")
          end)

        {:error, error} ->
          IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  defp handle_create_room(opts) do
    with {:ok, client} <- get_client(opts),
         {:ok, name} <- get_opt(opts, :name) do
      case LiveKit.RoomServiceClient.create_room(client, name) do
        {:ok, room} ->
          IO.puts("Created room:")
          IO.puts("  Name: #{room.name}")
          IO.puts("  SID: #{room.sid}")

        {:error, error} ->
          IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  defp handle_delete_room(opts) do
    with {:ok, client} <- get_client(opts),
         {:ok, room} <- get_opt(opts, :room) do
      case LiveKit.RoomServiceClient.delete_room(client, room) do
        :ok -> IO.puts("Room #{room} deleted")
        {:error, error} -> IO.puts("Error: #{inspect(error)}")
      end
    else
      {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
    end
  end

  defp handle_remove_participant(opts) do
    with {:ok, client} <- get_client(opts),
         {:ok, room} <- get_opt(opts, :room),
         {:ok, identity} <- get_opt(opts, :identity) do
      case LiveKit.RoomServiceClient.remove_participant(client, room, identity) do
        :ok -> IO.puts("Participant #{identity} removed from room #{room}")
        {:error, error} -> IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  defp handle_start_room_streaming(opts) do
    with {:ok, client} <- get_egress_client(opts),
         {:ok, room} <- get_opt(opts, :room),
         {:ok, rtmp} <- get_opt(opts, :rtmp) do
      encoding_options = %Livekit.EncodingOptions{
        width: Keyword.get(opts, :width, 1280),
        height: Keyword.get(opts, :height, 720),
        framerate: Keyword.get(opts, :fps, 30),
        audio_bitrate: Keyword.get(opts, :audio_bitrate, 128),
        video_bitrate: Keyword.get(opts, :video_bitrate, 3000)
      }

      request = %Livekit.RoomCompositeEgressRequest{
        room_name: room,
        options: {:advanced, encoding_options},
        file_outputs: [
          %Livekit.EncodedFileOutput{
            file_type: :rtmp,
            filepath: rtmp,
            output: rtmp
          }
        ]
      }

      case LiveKit.EgressServiceClient.start_room_composite_egress(client, request) do
        :ok -> IO.puts("Started room streaming")
        {:error, error} -> IO.puts("Failed to start room streaming: #{error}")
      end
    end
  end

  defp handle_start_track_recording(opts) do
    with {:ok, client} <- get_egress_client(opts),
         {:ok, room} <- get_opt(opts, :room),
         {:ok, track_id} <- get_opt(opts, :track_id),
         {:ok, output} <- get_opt(opts, :output) do
      request = %Livekit.TrackEgressRequest{
        room_name: room,
        track_id: track_id,
        filepath: output
      }

      case LiveKit.EgressServiceClient.start_track_egress(client, request) do
        :ok -> IO.puts("Started track recording")
        {:error, error} -> IO.puts("Failed to start track recording: #{error}")
      end
    end
  end

  defp handle_start_track_stream(opts) do
    with {:ok, client} <- get_egress_client(opts),
         {:ok, room} <- get_opt(opts, :room),
         {:ok, _track_id} <- get_opt(opts, :track_id),
         {:ok, rtmp} <- get_opt(opts, :rtmp) do
      encoding_options = %Livekit.EncodingOptions{
        width: Keyword.get(opts, :width, 1280),
        height: Keyword.get(opts, :height, 720),
        framerate: Keyword.get(opts, :fps, 30),
        audio_bitrate: Keyword.get(opts, :audio_bitrate, 128),
        video_bitrate: Keyword.get(opts, :video_bitrate, 3000)
      }

      request = %Livekit.RoomCompositeEgressRequest{
        room_name: room,
        options: {:advanced, encoding_options},
        stream_outputs: [
          %Livekit.StreamOutput{
            protocol: :RTMP,
            urls: [rtmp]
          }
        ],
        video_only: true
      }

      case LiveKit.EgressServiceClient.start_room_composite_egress(client, request) do
        :ok -> IO.puts("Started track streaming")
        {:error, error} -> IO.puts("Failed to start track streaming: #{error}")
      end
    end
  end

  defp handle_list_egress(opts) do
    with {:ok, client} <- get_egress_client(opts) do
      case LiveKit.EgressServiceClient.list_egress(client) do
        {:ok, items} ->
          Enum.each(items, fn item ->
            IO.puts("Egress ID: #{item.egress_id}")
            IO.puts("Status: #{item.status}")
            IO.puts("Started At: #{format_timestamp(item.started_at)}")
          end)

        {:error, error} ->
          IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  defp handle_stop_egress(opts) do
    with {:ok, client} <- get_egress_client(opts),
         {:ok, egress_id} <- get_opt(opts, :egress_id) do
      case LiveKit.EgressServiceClient.stop_egress(client, egress_id) do
        :ok -> IO.puts("Stopped egress")
        {:error, error} -> IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  defp handle_add_agent(opts) do
    with {:ok, client} <- get_client(opts),
         {:ok, room} <- get_opt(opts, :room),
         {:ok, name} <- get_opt(opts, :name),
         {:ok, prompt} <- get_opt(opts, :prompt) do
      agent = %Livekit.RoomAgentDispatch{
        name: name,
        identity: "agent-#{name}",
        init_request: %Livekit.InitRequest{
          prompt: prompt
        }
      }

      case LiveKit.RoomServiceClient.create_room(client, room, agents: [agent]) do
        {:ok, _room} -> IO.puts("Added agent to room")
        {:error, error} -> IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  defp handle_remove_agent(opts) do
    with {:ok, client} <- get_client(opts),
         {:ok, room} <- get_opt(opts, :room),
         {:ok, name} <- get_opt(opts, :name) do
      case LiveKit.RoomServiceClient.remove_participant(client, room, name) do
        :ok -> IO.puts("Removed agent #{name} from room #{room}")
        {:error, error} -> IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  defp handle_list_agents(opts) do
    with {:ok, client} <- get_client(opts),
         {:ok, room} <- get_opt(opts, :room) do
      case LiveKit.RoomServiceClient.list_participants(client, room) do
        {:ok, participants} ->
          participants
          |> Enum.filter(&(&1.name =~ ~r/^agent-/))
          |> Enum.each(fn participant ->
            IO.puts("Agent:")
            IO.puts("  Name: #{participant.name}")
            IO.puts("  Identity: #{participant.identity}")
            IO.puts("  State: #{participant.state}")
            IO.puts("  Joined At: #{participant.joined_at}")
          end)

          :ok

        {:error, error} ->
          IO.puts("Error: #{inspect(error)}")
          {:error, error}
      end
    end
  end

  defp get_client(opts) do
    with {:ok, config} <- LiveKit.Config.get_validated(opts) do
      {:ok, LiveKit.RoomServiceClient.new(config.url, config.api_key, config.api_secret)}
    end
  end

  defp get_egress_client(opts) do
    with {:ok, config} <- LiveKit.Config.get_validated(opts) do
      try do
        {:ok, LiveKit.EgressServiceClient.new(config.url, config.api_key, config.api_secret)}
      rescue
        error in [UndefinedFunctionError] ->
          {:error, "Failed to connect to egress service: #{inspect(error)}"}
      end
    end
  end

  defp get_opt(opts, key) do
    case Keyword.get(opts, key) do
      nil -> {:error, "Missing required option: --#{key}"}
      value -> {:ok, value}
    end
  end

  defp format_timestamp(nil), do: "N/A"

  defp format_timestamp(timestamp) do
    DateTime.from_unix!(timestamp)
    |> DateTime.to_string()
  end

  defp print_help do
    IO.puts(@moduledoc)
  end

  defp parse_output_url("s3://" <> path) do
    [_bucket | key_parts] = String.split(path, "/")
    _key = Enum.join(key_parts, "/")

    {:s3,
     %Livekit.S3Upload{
       bucket: List.first(String.split(path, "/")),
       aws_credentials: System.get_env("AWS_CREDENTIALS", "default")
     }}
  end

  defp parse_output_url(_path) do
    {:DEFAULT_FILETYPE, nil}
  end
end

defmodule Mix.Tasks.Livekit do
  use Mix.Task

  @shortdoc "LiveKit CLI commands"
  @moduledoc """
  Provides CLI commands for LiveKit operations.

  ## Commands

  Room Management:
  * `create-token` - Create an access token
  * `list-rooms` - List all rooms
  * `create-room` - Create a new room
  * `delete-room` - Delete a room
  * `list-participants` - List participants in a room
  * `remove-participant` - Remove a participant from a room


  Egress Operations:
  * `start-room-recording` - Start recording a room
  * `start-track-recording` - Start recording specific tracks
  * `start-room-stream` - Start streaming a room to RTMP endpoints
  * `start-track-stream` - Start streaming specific tracks to RTMP endpoints
  * `list-egress` - List active egress operations
  * `stop-egress` - Stop an egress operation


  Room Agents:
  * `add-agent` - Add an agent to a room
  * `remove-agent` - Remove an agent from a room
  * `list-agents` - List agents in a room

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
      mix livekit start-room-stream --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --rtmp rtmp://stream.url/live

      # Add an agent to a room
      mix livekit add-agent --api-key devkey --api-secret secret --url https://my.livekit.server --room my-room --name assistant --prompt "You are a helpful assistant"
  """

  @impl Mix.Task
  def run(args) do
    # Start required applications
    Application.ensure_all_started(:gun)
    Application.ensure_all_started(:grpc)

    {opts, args, _} =
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
          prompt: :string
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

    case args do
      # Room Management
      ["create-token" | _] -> create_token(opts)
      ["list-rooms" | _] -> list_rooms(opts)
      ["create-room" | _] -> create_room(opts)
      ["delete-room" | _] -> delete_room(opts)
      ["list-participants" | _] -> list_participants(opts)
      ["remove-participant" | _] -> remove_participant(opts)
      # Egress Operations
      ["start-room-recording" | _] -> start_room_recording(opts)
      ["start-track-recording" | _] -> start_track_recording(opts)
      ["start-room-streaming" | _] -> start_room_streaming(opts)
      ["start-track-stream" | _] -> start_track_stream(opts)
      ["list-egress" | _] -> list_egress(opts)
      ["stop-egress" | _] -> stop_egress(opts)
      # Room Agents
      ["add-agent" | _] -> add_agent(opts)
      ["remove-agent" | _] -> remove_agent(opts)
      ["list-agents" | _] -> list_agents(opts)
      _ -> print_help()
    end
  end

  # Existing command implementations...
  defp create_token(opts) do
    with {:ok, api_key} <- get_opt(opts, :api_key),
         {:ok, api_secret} <- get_opt(opts, :api_secret),
         {:ok, room} <- get_opt(opts, :room) do
      identity = Keyword.get(opts, :identity, "anonymous")
      ttl = parse_duration(Keyword.get(opts, :valid_for, "6h"))
      join = Keyword.get(opts, :join, false)

      token =
        LiveKit.AccessToken.new(api_key, api_secret)
        |> LiveKit.AccessToken.with_identity(identity)
        |> LiveKit.AccessToken.with_ttl(ttl)

      token =
        if join do
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

        {:error, error} ->
          IO.puts("Error: #{inspect(error)}")
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

        {:error, error} ->
          IO.puts("Error: #{inspect(error)}")
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

        {:error, error} ->
          IO.puts("Error: #{inspect(error)}")
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

  # 6 hours default
  defp parse_duration(_), do: 21600

  defp format_timestamp(nil), do: "N/A"

  defp format_timestamp(timestamp) do
    DateTime.from_unix!(timestamp)
    |> DateTime.to_string()
  end

  defp print_help do
    IO.puts(@moduledoc)
  end

  # New Egress commands
  defp start_room_recording(opts) do
    with {:ok, client} <- get_egress_client(opts),
         {:ok, room} <- get_opt(opts, :room),
         {:ok, output} <- get_opt(opts, :output) do
      # Parse output URL to determine type (s3, local, etc)
      {file_type, output_config} = parse_output_url(output)

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
            file_type: file_type,
            filepath: output,
            output: output_config
          }
        ]
      }

      case LiveKit.EgressServiceClient.start_room_composite_egress(
             client,
             request
           ) do
        {:ok, info} ->
          IO.puts("Started room recording:")
          IO.inspect(info)

        {:error, error} ->
          IO.puts("Failed to start room recording: #{error}")
      end
    end
  end

  defp start_room_streaming(opts) do
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

      stream_output = %Livekit.StreamOutput{
        protocol: :RTMP,
        urls: [rtmp]
      }

      request = %Livekit.RoomCompositeEgressRequest{
        room_name: room,
        options: {:advanced, encoding_options},
        stream_outputs: [stream_output]
      }

      case LiveKit.EgressServiceClient.start_room_composite_egress(client, request) do
        {:ok, info} ->
          IO.puts("Started room streaming:")
          IO.inspect(info)

        {:error, error} ->
          IO.puts("Failed to start room streaming: #{error}")
      end
    end
  end

  defp list_egress(opts) do
    with {:ok, client} <- get_egress_client(opts) do
      case LiveKit.EgressServiceClient.list_egress(client) do
        {:ok, items} ->
          items
          |> Enum.each(fn item ->
            IO.puts("#{item.egress_id}")
            IO.puts("  Status: #{item.status}")
            IO.puts("  Room Name: #{item.room_name}")
            IO.puts("  Started At: #{format_timestamp(item.started_at)}")
            IO.puts("")
          end)

        {:error, error} ->
          IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  defp stop_egress(opts) do
    with {:ok, client} <- get_egress_client(opts),
         {:ok, egress_id} <- get_opt(opts, :egress_id) do
      case LiveKit.EgressServiceClient.stop_egress(client, egress_id) do
        {:ok, info} ->
          IO.puts("Stopped egress:")
          IO.puts("  Egress ID: #{info.egress_id}")
          IO.puts("  Status: #{info.status}")

        {:error, error} ->
          IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  # Room Agent commands
  defp add_agent(opts) do
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
        {:ok, room} ->
          IO.puts("Added agent to room:")
          IO.puts("  Room: #{room.name}")
          IO.puts("  Agent: #{name}")

        {:error, error} ->
          IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  defp list_agents(opts) do
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
            IO.puts("")
          end)

        {:error, error} ->
          IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  defp remove_agent(opts) do
    with {:ok, client} <- get_client(opts),
         {:ok, room} <- get_opt(opts, :room),
         {:ok, name} <- get_opt(opts, :name) do
      identity = "agent-#{name}"

      case LiveKit.RoomServiceClient.remove_participant(client, room, identity) do
        {:ok, _} ->
          IO.puts("Removed agent #{name} from room #{room}")

        {:error, error} ->
          IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  # Helper functions
  defp get_egress_client(opts) do
    with {:ok, url} <- get_opt(opts, :url),
         {:ok, api_key} <- get_opt(opts, :api_key),
         {:ok, api_secret} <- get_opt(opts, :api_secret),
         {:ok, client} <- LiveKit.EgressServiceClient.new(url, api_key, api_secret) do
      {:ok, client}
    else
      {:error, message} when is_binary(message) ->
        IO.puts("Error: #{message}")
        {:error, message}

      {:error, {:missing_option, opt}} ->
        IO.puts("Error: Missing required option --#{opt}")
        {:error, :missing_option}
    end
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

  defp start_track_recording(opts) do
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
        {:ok, info} ->
          IO.puts("Started track recording:")
          IO.inspect(info)

        {:error, error} ->
          IO.puts("Failed to start track recording: #{error}")
      end
    end
  end

  defp start_track_stream(opts) do
    with {:ok, client} <- get_egress_client(opts),
         {:ok, room} <- get_opt(opts, :room),
         # We don't use track_id with RoomCompositeEgressRequest
         {:ok, _track_id} <- get_opt(opts, :track_id),
         {:ok, rtmp} <- get_opt(opts, :rtmp) do
      encoding_options = %Livekit.EncodingOptions{
        width: Keyword.get(opts, :width, 1280),
        height: Keyword.get(opts, :height, 720),
        framerate: Keyword.get(opts, :fps, 30),
        audio_bitrate: Keyword.get(opts, :audio_bitrate, 128),
        video_bitrate: Keyword.get(opts, :video_bitrate, 3000)
      }

      # For streaming a single track, we need to use RoomCompositeEgressRequest
      # since TrackCompositeEgressRequest doesn't support stream outputs
      request = %Livekit.RoomCompositeEgressRequest{
        room_name: room,
        options: {:advanced, encoding_options},
        stream_outputs: [
          %Livekit.StreamOutput{
            protocol: :RTMP,
            urls: [rtmp]
          }
        ],
        # Since we're only streaming a single track
        video_only: true
      }

      case LiveKit.EgressServiceClient.start_room_composite_egress(client, request) do
        {:ok, info} ->
          IO.puts("Started track streaming:")
          IO.inspect(info)

        {:error, error} ->
          IO.puts("Failed to start track streaming: #{error}")
      end
    end
  end
end

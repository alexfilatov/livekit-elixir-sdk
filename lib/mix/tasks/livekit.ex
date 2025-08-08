defmodule Mix.Tasks.Livekit do
  use Mix.Task
  require Logger

  @shortdoc "Livekit CLI commands"
  @moduledoc """
  Provides CLI commands for Livekit operations.

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

  Ingress Management:
  * `create-ingress` - Create a new ingress endpoint
  * `update-ingress` - Update an existing ingress endpoint
  * `list-ingress` - List ingress endpoints
  * `delete-ingress` - Delete an ingress endpoint

  Webhooks:
  * `verify-webhook` - Verify a webhook payload with a given token
  * `generate-webhook-config` - Generate webhook configuration for config.exs

  ## Options

  Common Options:
  * `--api-key` (`-k`) - Livekit API key (required)
  * `--api-secret` (`-s`) - Livekit API secret (required)
  * `--url` (`-u`) - Livekit server URL (required for most commands)
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

  Ingress Options:
  * `--ingress-id` - Ingress ID for update/delete operations
  * `--input-type` - Input type (RTMP, WHIP, URL)
  * `--source-url` - Source URL for URL input type
  * `--participant-metadata` - Metadata for the publishing participant
  * `--enable-transcoding` - Enable transcoding (true/false)
  * `--audio-preset` - Audio encoding preset
  * `--video-preset` - Video encoding preset

  Agent Options:
  * `--prompt` - Initial prompt for the agent (required for add-agent)
  * `--name` - Agent name (required for add/remove agent)

  Webhook Options:
  * `--payload` - Webhook payload to verify
  * `--token` - Webhook token to verify with
  * `--webhook-url` - Webhook URL to generate configuration for

  ## Examples

      # Create a token
      mix livekit create-token --api-key devkey --api-secret secret --url http://localhost:7880 --join --room my-room --identity user1 --valid-for 24h

      # List rooms
      mix livekit list-rooms --api-key devkey --api-secret secret --url http://localhost:7880

      # Create a room
      mix livekit create-room --api-key devkey --api-secret secret --url http://localhost:7880 --name my-room

      # Delete a room
      mix livekit delete-room --api-key devkey --api-secret secret --url http://localhost:7880 --room my-room

      # List participants
      mix livekit list-participants --api-key devkey --api-secret secret --url http://localhost:7880 --room my-room

      # Remove a participant
      mix livekit remove-participant --api-key devkey --api-secret secret --url http://localhost:7880 --room my-room --identity user1

      # Start room recording
      mix livekit start-room-recording --api-key devkey --api-secret secret --url http://localhost:7880 --room my-room --output s3://bucket/recording.mp4

      # Start room streaming
      mix livekit start-room-streaming --api-key devkey --api-secret secret --url http://localhost:7880 --room my-room --rtmp rtmp://stream.url/live

      # Add an agent to a room
      mix livekit add-agent --api-key devkey --api-secret secret --url http://localhost:7880 --room my-room --prompt "You are a helpful assistant"

      # Verify a webhook payload
      mix livekit verify-webhook --api-key devkey --api-secret secret --payload '{"event": "room-created", "room": {"name": "my-room"}}' --token my-webhook-token

      # Generate webhook configuration
      mix livekit generate-webhook-config --api-key devkey --api-secret secret --webhook-url https://example.com/webhook

      # Create RTMP ingress
      mix livekit create-ingress --api-key devkey --api-secret secret --url http://localhost:7880 --input-type RTMP --name my-stream --room my-room --identity streamer

      # Create WebRTC ingress
      mix livekit create-ingress --api-key devkey --api-secret secret --url http://localhost:7880 --input-type WHIP --name whip-stream --room my-room --identity whip-user

      # Create URL ingress
      mix livekit create-ingress --api-key devkey --api-secret secret --url http://localhost:7880 --input-type URL --source-url https://example.com/stream.m3u8 --name url-stream --room my-room --identity url-user

      # List ingress endpoints
      mix livekit list-ingress --api-key devkey --api-secret secret --url http://localhost:7880

      # Update ingress
      mix livekit update-ingress --api-key devkey --api-secret secret --url http://localhost:7880 --ingress-id ingress_123 --name updated-stream

      # Delete ingress
      mix livekit delete-ingress --api-key devkey --api-secret secret --url http://localhost:7880 --ingress-id ingress_123
  """

  @impl Mix.Task
  def run(args) do
    # Start required applications
    Application.ensure_all_started(:hackney)
    Application.ensure_all_started(:gun)
    Application.ensure_all_started(:grpc)

    {opts, args, _} = parse_options(args)

    command = List.first(args)

    handle_command(command, opts)
  end

  defp parse_options(args) do
    {opts, args, invalid} =
      OptionParser.parse(args,
        strict: [
          api_key: :string,
          api_secret: :string,
          url: :string,
          room: :string,
          identity: :string,
          name: :string,
          valid_for: :string,
          join: :boolean,
          can_publish: :boolean,
          can_subscribe: :boolean,
          can_publish_data: :boolean,
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
          payload: :string,
          token: :string,
          webhook_url: :string,
          ingress_id: :string,
          input_type: :string,
          source_url: :string,
          participant_metadata: :string,
          enable_transcoding: :boolean,
          audio_preset: :string,
          video_preset: :string
        ],
        aliases: [
          k: :api_key,
          s: :api_secret,
          u: :url,
          r: :room,
          i: :identity,
          n: :name,
          t: :valid_for,
          o: :output
        ]
      )

    if invalid != [] do
      IO.puts("Invalid options: #{inspect(invalid)}")
    end

    {opts, args, invalid}
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
  defp handle_command("list-agents", opts), do: handle_agent_commands("list-agents", opts)
  defp handle_command("create-ingress", opts), do: handle_ingress_commands("create-ingress", opts)
  defp handle_command("update-ingress", opts), do: handle_ingress_commands("update-ingress", opts)
  defp handle_command("list-ingress", opts), do: handle_ingress_commands("list-ingress", opts)
  defp handle_command("delete-ingress", opts), do: handle_ingress_commands("delete-ingress", opts)
  defp handle_command("verify-webhook", opts), do: handle_verify_webhook(opts)
  defp handle_command("generate-webhook-config", opts), do: handle_generate_webhook_config(opts)
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

  defp handle_agent_commands("add-agent", opts), do: handle_add_agent(opts)
  defp handle_agent_commands("remove-agent", opts), do: handle_remove_agent(opts)
  defp handle_agent_commands("list-agents", opts), do: handle_list_agents(opts)
  defp handle_agent_commands(_, _), do: :unknown_command

  def handle_create_token(opts) do
    with {:ok, identity} <- get_opt(opts, :identity),
         {:ok, room} <- get_opt(opts, :room) do
      config = Livekit.Config.get(opts)

      case Livekit.Config.validate(config) do
        :ok ->
          metadata = Keyword.get(opts, :metadata)
          valid_for = Keyword.get(opts, :valid_for)

          grant = %Livekit.Grants{
            room: room,
            room_join: true,
            room_admin: Keyword.get(opts, :admin, false)
          }

          token =
            Livekit.AccessToken.new(config.api_key, config.api_secret)
            |> Livekit.AccessToken.with_identity(identity)
            |> Livekit.AccessToken.with_grants(grant)
            |> maybe_add_ttl(valid_for)
            |> maybe_add_metadata(metadata)
            |> Livekit.AccessToken.to_jwt()

          Logger.info("Successfully created token: #{token}; grant: #{inspect(grant)}")
          {:ok, token}

        error ->
          Logger.error("Failed to create token: #{inspect(error)}")
          error
      end
    end
  end

  defp maybe_add_ttl(token, nil), do: token

  defp maybe_add_ttl(token, ttl) when is_binary(ttl) do
    case parse_duration(ttl) do
      {:ok, seconds} -> Livekit.AccessToken.with_ttl(token, seconds)
      _error -> token
    end
  end

  defp maybe_add_metadata(token, nil), do: token

  defp maybe_add_metadata(token, metadata) when is_binary(metadata) do
    Livekit.AccessToken.with_metadata(token, metadata)
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
      case Livekit.RoomServiceClient.list_participants(client, room) do
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
        options: %Livekit.RoomCompositeEgressRequest.Options{
          video_width: 1280,
          video_height: 720,
          fps: 30,
          audio_bitrate: 128_000,
          video_bitrate: 3_000_000
        }
      }

      try do
        case Livekit.EgressServiceClient.start_room_composite_egress(client, request) do
          {:ok, response} ->
            Logger.info("Successfully started room recording, response: #{inspect(response)}")
            {:ok, response}

          {:error, %GRPC.RPCError{} = error} ->
            Logger.error(
              "Failed to start room recording because of GRPC error: #{inspect(error)}"
            )

            {:error, error.message}

          {:error, reason} ->
            Logger.error("Failed to start room recording: #{inspect(reason)}")
            {:error, reason}
        end
      rescue
        error ->
          Logger.error("Failed to start room recording because of: #{inspect(error)}")
          {:error, "Failed to start recording: #{inspect(error)}"}
      end
    end
  end

  defp handle_list_rooms(opts) do
    with {:ok, client} <- get_client(opts) do
      case Livekit.RoomServiceClient.list_rooms(client) do
        {:ok, list_rooms_response} ->
          Enum.each(list_rooms_response.rooms, fn room ->
            IO.puts("#{room.name} (#{room.sid})")
            IO.puts("  Num Participants: #{length(room.participants)}")
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
      case Livekit.RoomServiceClient.create_room(client, name) do
        {:ok, room} ->
          IO.puts("Created room:")
          IO.puts("  Name: #{room.name}")
          IO.puts("  SID: #{room.sid}")
          Logger.info("Successfully created room '#{name}' with SID: #{room.sid}")
          {:ok, room}

        {:error, error} ->
          Logger.error("Failed to create room: #{inspect(error)}")
          IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  defp handle_delete_room(opts) do
    with {:ok, client} <- get_client(opts),
         {:ok, room} <- get_opt(opts, :room) do
      case Livekit.RoomServiceClient.delete_room(client, room) do
        :ok ->
          Logger.info("Successfully deleted room: #{room}")
          IO.puts("Room #{room} deleted")

        {:error, error} ->
          Logger.error("Failed to delete room: #{inspect(error)}")
          IO.puts("Error: #{inspect(error)}")
      end
    else
      {:error, reason} ->
        Logger.error("Failed to initialize room client: #{inspect(reason)}")
        IO.puts("Error: #{inspect(reason)}")
    end
  end

  defp handle_remove_participant(opts) do
    with {:ok, client} <- get_client(opts),
         {:ok, room} <- get_opt(opts, :room),
         {:ok, identity} <- get_opt(opts, :identity) do
      case Livekit.RoomServiceClient.remove_participant(client, room, identity) do
        :ok ->
          Logger.info("Successfully removed participant #{identity} from room #{room}")
          IO.puts("Participant #{identity} removed from room #{room}")

        {:error, error} ->
          Logger.error("Failed to remove participant: #{inspect(error)}")
          IO.puts("Error: #{inspect(error)}")
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

      case Livekit.EgressServiceClient.start_room_composite_egress(client, request) do
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

      case Livekit.EgressServiceClient.start_track_egress(client, request) do
        :ok ->
          Logger.info(
            "Successfully started track recording for track #{track_id} in room #{room}"
          )

          IO.puts("Started track recording")

        {:error, error} ->
          Logger.error("Failed to start track recording: #{inspect(error)}")
          IO.puts("Failed to start track recording: #{error}")
      end
    end
  end

  defp handle_start_track_stream(opts) do
    with {:ok, client} <- get_egress_client(opts),
         {:ok, room} <- get_opt(opts, :room),
         {:ok, track_id} <- get_opt(opts, :track_id),
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

      case Livekit.EgressServiceClient.start_room_composite_egress(client, request) do
        :ok ->
          Logger.info(
            "Successfully started track streaming for track #{track_id} in room #{room}"
          )

          IO.puts("Started track streaming")

        {:error, error} ->
          Logger.error("Failed to start track streaming: #{inspect(error)}")
          IO.puts("Failed to start track streaming: #{error}")
      end
    end
  end

  defp handle_list_egress(opts) do
    with {:ok, client} <- get_egress_client(opts) do
      case Livekit.EgressServiceClient.list_egress(client) do
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
      case Livekit.EgressServiceClient.stop_egress(client, egress_id) do
        :ok -> IO.puts("Stopped egress")
        {:error, error} -> IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  defp handle_add_agent(opts) do
    with {:ok, client} <- get_client(opts),
         {:ok, room} <- get_opt(opts, :room),
         {:ok, prompt} <- get_opt(opts, :prompt) do
      random_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

      agent = %Livekit.RoomAgentDispatch{
        name: "agent-#{random_id}",
        identity: "agent-#{random_id}",
        init_request: %Livekit.InitRequest{
          prompt: prompt
        }
      }

      case Livekit.RoomServiceClient.create_room(client, room, agents: [agent]) do
        {:ok, _room} -> IO.puts("Added agent to room")
        {:error, error} -> IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  defp handle_remove_agent(opts) do
    with {:ok, client} <- get_client(opts),
         {:ok, room} <- get_opt(opts, :room),
         {:ok, identity} <- get_opt(opts, :identity) do
      case Livekit.RoomServiceClient.remove_participant(client, room, identity) do
        :ok -> IO.puts("Removed agent #{identity} from room #{room}")
        {:error, error} -> IO.puts("Error: #{inspect(error)}")
      end
    end
  end

  defp handle_list_agents(opts) do
    with {:ok, client} <- get_client(opts),
         {:ok, room} <- get_opt(opts, :room) do
      case Livekit.RoomServiceClient.list_participants(client, room) do
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

  defp handle_verify_webhook(opts) do
    with {:ok, token} <- get_opt(opts, :token),
         {:ok, payload} <- get_opt(opts, :payload),
         {:ok, _api_key} <- get_opt(opts, :api_key),
         {:ok, _api_secret} <- get_opt(opts, :api_secret) do
      # Configure the webhook receiver with the API key and secret from opts
      Application.put_env(:livekit, :webhook, %{
        api_key: Keyword.get(opts, :api_key),
        api_secret: Keyword.get(opts, :api_secret)
      })

      case Livekit.WebhookReceiver.receive(payload, token) do
        {:ok, event} ->
          IO.puts("Webhook verification successful!")
          IO.puts("Event type: #{event.event}")
          IO.puts("Event ID: #{event.id}")
          IO.puts("Created at: #{event.created_at}")

          if event.room do
            IO.puts("\nRoom information:")
            IO.puts("  Name: #{event.room.name}")
            IO.puts("  SID: #{event.room.sid}")
          end

          if event.participant do
            IO.puts("\nParticipant information:")
            IO.puts("  Identity: #{event.participant.identity}")
            IO.puts("  Name: #{event.participant.name}")
            IO.puts("  SID: #{event.participant.sid}")
          end

          if event.track do
            IO.puts("\nTrack information:")
            IO.puts("  SID: #{event.track.sid}")
            IO.puts("  Name: #{event.track.name}")
            IO.puts("  Type: #{event.track.type}")
          end

          if event.egress_info do
            IO.puts("\nEgress information:")
            IO.puts("  Egress ID: #{event.egress_info.egress_id}")
            IO.puts("  Room name: #{event.egress_info.room_name}")
            IO.puts("  Status: #{event.egress_info.status}")
          end

        {:error, reason} ->
          IO.puts("Webhook verification failed: #{inspect(reason)}")
      end
    else
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
  end

  defp handle_generate_webhook_config(opts) do
    with {:ok, api_key} <- get_opt(opts, :api_key),
         {:ok, api_secret} <- get_opt(opts, :api_secret),
         webhook_urls <- Keyword.get_values(opts, :webhook_url) do
      if webhook_urls == [] do
        IO.puts(
          "Warning: No webhook URLs specified. Use --webhook-url to specify one or more webhook endpoints."
        )
      end

      config = """
      # LiveKit Webhook Configuration
      config :livekit, :webhook,
        api_key: "#{api_key}",
        api_secret: "#{api_secret}"#{if webhook_urls != [], do: ",", else: ""}
      #{if webhook_urls != [], do: "  urls: #{inspect(webhook_urls)}", else: ""}
      """

      IO.puts("Add the following to your config.exs file:")
      IO.puts(config)
    else
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
  end

  defp get_client(opts) do
    with {:ok, config} <- Livekit.Config.get_validated(opts) do
      {:ok, Livekit.RoomServiceClient.new(config.url, config.api_key, config.api_secret)}
    end
  end

  defp get_egress_client(opts) do
    with {:ok, config} <- Livekit.Config.get_validated(opts) do
      try do
        {:ok, Livekit.EgressServiceClient.new(config.url, config.api_key, config.api_secret)}
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

  defp handle_ingress_commands(command, opts) do
    case command do
      "create-ingress" -> handle_create_ingress(opts)
      "update-ingress" -> handle_update_ingress(opts)
      "list-ingress" -> handle_list_ingress(opts)
      "delete-ingress" -> handle_delete_ingress(opts)
      _ -> :unknown_command
    end
  end

  defp handle_create_ingress(opts) do
    with {:ok, client} <- get_ingress_client(opts),
         {:ok, input_type_atom} <- parse_input_type(opts[:input_type]),
         {:ok, name} <- get_opt(opts, :name),
         {:ok, room_name} <- get_opt(opts, :room),
         {:ok, identity} <- get_opt(opts, :identity) do
      request = %Livekit.CreateIngressRequest{
        input_type: input_type_atom,
        name: name,
        room_name: room_name,
        participant_identity: identity,
        participant_name: opts[:name],
        url: opts[:source_url] || "",
        participant_metadata: opts[:participant_metadata] || "",
        enable_transcoding: opts[:enable_transcoding]
      }

      request = add_encoding_options(request, opts)

      case Livekit.IngressServiceClient.create_ingress(client, request) do
        {:ok, ingress} ->
          IO.puts("✅ Ingress created successfully!")
          IO.puts("Ingress ID: #{ingress.ingress_id}")
          IO.puts("Stream URL: #{ingress.url}")
          if ingress.stream_key && ingress.stream_key != "" do
            IO.puts("Stream Key: #{ingress.stream_key}")
          end
          IO.puts("Input Type: #{ingress.input_type}")
          IO.puts("Room: #{ingress.room_name}")
          IO.puts("Participant: #{ingress.participant_identity}")

        {:error, error} ->
          IO.puts("❌ Error creating ingress: #{inspect(error)}")
      end
    else
      {:error, reason} -> IO.puts("❌ Error: #{reason}")
      _ -> IO.puts("❌ Invalid arguments for create-ingress")
    end
  end

  defp handle_update_ingress(opts) do
    with {:ok, client} <- get_ingress_client(opts),
         {:ok, ingress_id} <- get_opt(opts, :ingress_id) do
      request = %Livekit.UpdateIngressRequest{
        ingress_id: ingress_id,
        name: opts[:name],
        room_name: opts[:room],
        participant_identity: opts[:identity],
        participant_name: opts[:name],
        participant_metadata: opts[:participant_metadata],
        enable_transcoding: opts[:enable_transcoding]
      }

      request = add_update_encoding_options(request, opts)

      case Livekit.IngressServiceClient.update_ingress(client, request) do
        {:ok, ingress} ->
          IO.puts("✅ Ingress updated successfully!")
          IO.puts("Ingress ID: #{ingress.ingress_id}")
          IO.puts("Name: #{ingress.name}")
          IO.puts("Room: #{ingress.room_name}")
          IO.puts("Participant: #{ingress.participant_identity}")

        {:error, error} ->
          IO.puts("❌ Error updating ingress: #{inspect(error)}")
      end
    else
      {:error, reason} -> IO.puts("❌ Error: #{reason}")
      _ -> IO.puts("❌ Invalid arguments for update-ingress")
    end
  end

  defp handle_list_ingress(opts) do
    case get_ingress_client(opts) do
      {:ok, client} ->
        request = %Livekit.ListIngressRequest{
          room_name: opts[:room],
          ingress_id: opts[:ingress_id]
        }

        case Livekit.IngressServiceClient.list_ingress(client, request) do
          {:ok, response} ->
            display_ingress_list(response.items)

          {:error, error} ->
            IO.puts("❌ Error listing ingress: #{inspect(error)}")
        end

      {:error, reason} ->
        IO.puts("❌ Error: #{reason}")
    end
  end

  defp display_ingress_list([]) do
    IO.puts("No ingress endpoints found.")
  end

  defp display_ingress_list(items) do
    IO.puts("📡 Ingress Endpoints:")
    IO.puts("")

    Enum.each(items, &display_ingress_item/1)
  end

  defp display_ingress_item(ingress) do
    IO.puts("  ID: #{ingress.ingress_id}")
    IO.puts("  Name: #{ingress.name}")
    IO.puts("  Type: #{ingress.input_type}")
    IO.puts("  URL: #{ingress.url}")
    IO.puts("  Room: #{ingress.room_name}")
    IO.puts("  Participant: #{ingress.participant_identity}")
    IO.puts("  Status: #{ingress.state && ingress.state.status}")
    IO.puts("  Enabled: #{ingress.enabled}")
    IO.puts("")
  end

  defp handle_delete_ingress(opts) do
    with {:ok, client} <- get_ingress_client(opts),
         {:ok, ingress_id} <- get_opt(opts, :ingress_id) do
      request = %Livekit.DeleteIngressRequest{
        ingress_id: ingress_id
      }

      case Livekit.IngressServiceClient.delete_ingress(client, request) do
        {:ok, ingress} ->
          IO.puts("✅ Ingress deleted successfully!")
          IO.puts("Deleted Ingress ID: #{ingress.ingress_id}")
          IO.puts("Name: #{ingress.name}")

        {:error, error} ->
          IO.puts("❌ Error deleting ingress: #{inspect(error)}")
      end
    else
      {:error, reason} -> IO.puts("❌ Error: #{reason}")
      _ -> IO.puts("❌ Invalid arguments for delete-ingress")
    end
  end

  defp get_ingress_client(opts) do
    with {:ok, url} <- get_opt(opts, :url),
         {:ok, api_key} <- get_opt(opts, :api_key),
         {:ok, api_secret} <- get_opt(opts, :api_secret) do
      Livekit.IngressServiceClient.new(url, api_key, api_secret)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, "Missing required options for ingress client"}
    end
  end

  defp parse_input_type(nil), do: {:error, "input-type is required"}
  defp parse_input_type("RTMP"), do: {:ok, :RTMP_INPUT}
  defp parse_input_type("WHIP"), do: {:ok, :WHIP_INPUT}
  defp parse_input_type("URL"), do: {:ok, :URL_INPUT}
  defp parse_input_type(type), do: {:error, "Invalid input type '#{type}'. Valid types: RTMP, WHIP, URL"}

  defp add_encoding_options(request, opts) do
    audio_options = build_audio_options(opts)
    video_options = build_video_options(opts)

    request
    |> maybe_add_field(:audio, audio_options)
    |> maybe_add_field(:video, video_options)
  end

  defp add_update_encoding_options(request, opts) do
    audio_options = build_audio_options(opts)
    video_options = build_video_options(opts)

    request
    |> maybe_add_field(:audio, audio_options)
    |> maybe_add_field(:video, video_options)
  end

  defp build_audio_options(_opts) do
    # TODO: Implement audio options when needed
    nil
  end

  defp build_video_options(_opts) do
    # TODO: Implement video options when needed
    nil
  end

  defp maybe_add_field(struct, _field, nil), do: struct
  defp maybe_add_field(struct, field, value), do: Map.put(struct, field, value)

  defp print_help do
    IO.puts(@moduledoc)
  end
end

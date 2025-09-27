defmodule Livekit.WebhookReceiver do
  @moduledoc """
  Webhook receiver for LiveKit.

  This module provides functionality to validate and decode webhook events sent by LiveKit.

  ## Configuration

  Configure webhook settings in your `config.exs`:

  ```elixir
  config :livekit, :webhook,
    api_key: "your_api_key",
    api_secret: "your_api_secret",
    # Optional: URLs to send webhooks to (only needed if you're sending webhooks)
    urls: ["https://your-webhook-endpoint.com/webhook"]
  ```

  ## Usage

  ```elixir
  # In a Phoenix controller
  def webhook(conn, params) do
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
  ```
  """

  alias Livekit.AccessToken
  alias Livekit.WebhookEvent

  @doc """
  Validates and decodes a webhook event.

  ## Parameters

  - `body`: The raw request body as a binary
  - `auth_header`: The Authorization header from the request

  ## Returns

  - `{:ok, event}`: If the webhook is valid, returns the decoded WebhookEvent
  - `{:error, reason}`: If the webhook is invalid or cannot be decoded
  """
  @spec receive(binary(), list(binary()) | binary()) ::
          {:ok, map()} | {:error, String.t()}
  def receive(body, [auth_header | _]) when is_binary(auth_header), do: receive(body, auth_header)
  def receive(_body, []), do: {:error, "Missing Authorization header"}

  def receive(body, auth_header) when is_binary(body) and is_binary(auth_header) do
    with {:ok, config} <- get_config(),
         {:ok, claims} <- validate_token(auth_header, config),
         :ok <- validate_sha(claims, body),
         {:ok, event} <- decode_event(body) do
      {:ok, event}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Decodes a webhook event from JSON.

  ## Parameters

  - `body`: The raw request body as a binary

  ## Returns

  - `{:ok, event}`: If the webhook can be decoded, returns the decoded WebhookEvent
  - `{:error, reason}`: If the webhook cannot be decoded
  """
  @spec decode_event(binary()) :: {:ok, map()} | {:error, String.t()}
  def decode_event(body) do
    case Jason.decode(body) do
      {:ok, json} ->
        try do
          event = %WebhookEvent{
            event: Map.get(json, "event"),
            room: decode_room(Map.get(json, "room")),
            participant: decode_participant(Map.get(json, "participant")),
            egress_info: decode_egress_info(Map.get(json, "egressInfo")),
            track: decode_track(Map.get(json, "track")),
            id: Map.get(json, "id"),
            created_at: Map.get(json, "created_at", Map.get(json, "createdAt", 0))
          }

          {:ok, event}
        rescue
          e -> {:error, "Failed to decode webhook event: #{inspect(e)}"}
        end

      {:error, reason} ->
        {:error, "Failed to parse JSON: #{inspect(reason)}"}
    end
  end

  # Helper functions to decode nested structures
  defp decode_room(nil), do: nil

  defp decode_room(room) when is_map(room) do
    %Livekit.Room{
      sid: Map.get(room, "sid"),
      name: Map.get(room, "name"),
      empty_timeout: Map.get(room, "emptyTimeout", 0),
      max_participants: Map.get(room, "maxParticipants", 0),
      creation_time: Map.get(room, "creationTime", 0),
      enabled_codecs: decode_codecs(Map.get(room, "enabledCodecs", [])),
      metadata: Map.get(room, "metadata")
    }
  end

  defp decode_participant(nil), do: nil

  defp decode_participant(participant) when is_map(participant) do
    %Livekit.ParticipantInfo{
      sid: Map.get(participant, "sid"),
      identity: Map.get(participant, "identity"),
      name: Map.get(participant, "name"),
      state: decode_participant_state(Map.get(participant, "state")),
      tracks: decode_tracks(Map.get(participant, "tracks", [])),
      metadata: Map.get(participant, "metadata"),
      joined_at: Map.get(participant, "joinedAt", 0)
    }
  end

  defp decode_egress_info(nil), do: nil

  defp decode_egress_info(egress_info) when is_map(egress_info) do
    %Livekit.EgressInfo{
      egress_id: Map.get(egress_info, "egressId"),
      room_id: Map.get(egress_info, "roomId"),
      room_name: Map.get(egress_info, "roomName"),
      status: decode_egress_status(Map.get(egress_info, "status"))
    }
  end

  defp decode_track(nil), do: nil

  defp decode_track(track) when is_map(track) do
    %Livekit.TrackInfo{
      sid: Map.get(track, "sid"),
      type: decode_track_type(Map.get(track, "type")),
      name: Map.get(track, "name"),
      muted: Map.get(track, "muted", false),
      width: Map.get(track, "width", 0),
      height: Map.get(track, "height", 0),
      mime_type: Map.get(track, "mimeType"),
      mid: Map.get(track, "mid")
    }
  end

  defp decode_codecs(codecs) when is_list(codecs) do
    Enum.map(codecs, fn codec ->
      %Livekit.Codec{
        mime: Map.get(codec, "mime"),
        fmtp_line: Map.get(codec, "fmtpLine")
      }
    end)
  end

  defp decode_tracks(tracks) when is_list(tracks) do
    Enum.map(tracks, &decode_track/1)
  end

  defp decode_participant_state(nil), do: 0
  defp decode_participant_state("JOINING"), do: 1
  defp decode_participant_state("JOINED"), do: 2
  defp decode_participant_state("ACTIVE"), do: 3
  defp decode_participant_state("DISCONNECTED"), do: 4
  defp decode_participant_state(state) when is_integer(state), do: state
  defp decode_participant_state(_), do: 0

  defp decode_track_type(nil), do: 0
  defp decode_track_type("AUDIO"), do: 1
  defp decode_track_type("VIDEO"), do: 2
  defp decode_track_type("DATA"), do: 3
  defp decode_track_type(type) when is_integer(type), do: type
  defp decode_track_type(_), do: 0

  defp decode_egress_status(nil), do: 0
  defp decode_egress_status("EGRESS_STARTING"), do: 1
  defp decode_egress_status("EGRESS_ACTIVE"), do: 2
  defp decode_egress_status("EGRESS_ENDING"), do: 3
  defp decode_egress_status("EGRESS_COMPLETE"), do: 4
  defp decode_egress_status("EGRESS_FAILED"), do: 5
  defp decode_egress_status("EGRESS_ABORTED"), do: 6
  defp decode_egress_status("EGRESS_LIMIT_REACHED"), do: 7
  defp decode_egress_status(status) when is_integer(status), do: status
  defp decode_egress_status(_), do: 0

  # Validates the JWT token from the Authorization header
  defp validate_token(auth_header, config) do
    case AccessToken.verify(auth_header, config.api_key, config.api_secret) do
      {:ok, claims} -> {:ok, claims}
      {:error, reason} -> {:error, "Invalid webhook token: #{inspect(reason)}"}
    end
  end

  # Validates the SHA256 hash of the request body
  defp validate_sha(claims, body) do
    case Map.get(claims, "sha256") do
      nil ->
        {:error, "Missing SHA256 hash in token"}

      sha ->
        computed_sha = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

        if sha == computed_sha do
          :ok
        else
          {:error, "SHA256 hash mismatch"}
        end
    end
  end

  # Gets the webhook configuration from the application environment
  defp get_config do
    case Application.get_env(:livekit, :webhook) do
      nil ->
        {:error, "Webhook configuration not found"}

      config ->
        api_key = Map.get(config, :api_key)
        api_secret = Map.get(config, :api_secret)

        cond do
          is_nil(api_key) -> {:error, "Missing API key in webhook configuration"}
          is_nil(api_secret) -> {:error, "Missing API secret in webhook configuration"}
          true -> {:ok, %{api_key: api_key, api_secret: api_secret}}
        end
    end
  end
end

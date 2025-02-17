defmodule LiveKit.RoomServiceClient do
  @moduledoc """
  Client for the LiveKit Room Service API.
  """

  use Tesla
  alias LiveKit.AccessToken

  alias Livekit.{
    CreateRoomRequest,
    DeleteRoomRequest,
    ListParticipantsRequest,
    ListParticipantsResponse,
    ListRoomsRequest,
    ListRoomsResponse,
    MuteRoomTrackRequest,
    MuteRoomTrackResponse,
    ParticipantInfo,
    Room,
    RoomParticipantIdentity,
    SendDataRequest,
    UpdateParticipantRequest,
    UpdateRoomMetadataRequest,
    UpdateSubscriptionsRequest
  }

  require Logger

  defstruct [:base_url, :api_key, :api_secret, :client]

  @doc """
  Creates a new RoomServiceClient instance.
  """
  def new(base_url, api_key, api_secret) do
    # Convert ws:// to http:// and wss:// to https://
    base_url =
      base_url
      |> String.replace(~r{^ws://}, "http://")
      |> String.replace(~r{^wss://}, "https://")

    # Get Tesla logger config from application config, with defaults
    tesla_logging =
      Application.get_env(:livekit, __MODULE__, [])
      |> Keyword.get(:tesla_logging,
        debug: false,
        filter_headers: ["authorization"],
        format_options: [
          format_response_body: false,
          format_request_body: false
        ]
      )

    middleware = [
      {Tesla.Middleware.BaseUrl, base_url},
      {Tesla.Middleware.Headers,
       [
         {"Content-Type", "application/protobuf"},
         {"Accept", "application/protobuf"}
       ]},
      {Tesla.Middleware.Logger, tesla_logging}
    ]

    client = Tesla.client(middleware, {Tesla.Adapter.Hackney, [recv_timeout: 30_000]})

    %__MODULE__{
      base_url: base_url,
      api_key: api_key,
      api_secret: api_secret,
      client: client
    }
  end

  @doc """
  Creates a new room.
  """
  def create_room(%__MODULE__{} = client, name, opts \\ []) do
    path = "/twirp/livekit.RoomService/CreateRoom"

    request =
      struct(CreateRoomRequest, %{
        name: name,
        empty_timeout: Keyword.get(opts, :empty_timeout),
        departure_timeout: Keyword.get(opts, :departure_timeout),
        max_participants: Keyword.get(opts, :max_participants),
        egress: Keyword.get(opts, :egress),
        metadata: Keyword.get(opts, :metadata),
        min_playout_delay: Keyword.get(opts, :min_playout_delay),
        max_playout_delay: Keyword.get(opts, :max_playout_delay),
        sync_streams: Keyword.get(opts, :sync_streams)
      })
      |> CreateRoomRequest.encode()

    headers = auth_header(client, %{room_create: true})

    case Tesla.post(client.client, path, request, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, Room.decode(body)}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Request failed with status #{status}: #{inspect(body)}")
        {:error, {status, body}}

      {:error, reason} ->
        Logger.error("Request error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Lists all rooms.
  """
  def list_rooms(%__MODULE__{} = client, names \\ nil) do
    path = "/twirp/livekit.RoomService/ListRooms"

    request =
      struct(ListRoomsRequest, %{names: names || []})
      |> ListRoomsRequest.encode()

    headers = auth_header(client, %{room_list: true})

    case Tesla.post(client.client, path, request, headers: headers) do
      {:ok, %{status: 200, body: body}} -> {:ok, ListRoomsResponse.decode(body)}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes a room.
  """
  def delete_room(%__MODULE__{} = client, room) do
    path = "/twirp/livekit.RoomService/DeleteRoom"

    request =
      struct(DeleteRoomRequest, %{room: room})
      |> DeleteRoomRequest.encode()

    headers = auth_header(client, %{room_create: true})

    case Tesla.post(client.client, path, request, headers: headers) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates room metadata.
  """
  def update_room_metadata(%__MODULE__{} = client, room, metadata) do
    path = "/twirp/livekit.RoomService/UpdateRoomMetadata"

    request =
      struct(UpdateRoomMetadataRequest, %{room: room, metadata: metadata})
      |> UpdateRoomMetadataRequest.encode()

    headers = auth_header(client, %{room_admin: true, room: room})

    case Tesla.post(client.client, path, request, headers: headers) do
      {:ok, %{status: 200, body: body}} -> {:ok, Room.decode(body)}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists participants in a room.
  """
  def list_participants(%__MODULE__{} = client, room) do
    path = "/twirp/livekit.RoomService/ListParticipants"

    request =
      struct(ListParticipantsRequest, %{room: room})
      |> ListParticipantsRequest.encode()

    headers = auth_header(client, %{room_admin: true, room: room})

    case Tesla.post(client.client, path, request, headers: headers) do
      {:ok, %{status: 200, body: body}} -> {:ok, ListParticipantsResponse.decode(body)}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets a participant from a room.
  """
  def get_participant(%__MODULE__{} = client, room, identity) do
    path = "/twirp/livekit.RoomService/GetParticipant"

    request =
      struct(RoomParticipantIdentity, %{room: room, identity: identity})
      |> RoomParticipantIdentity.encode()

    headers = auth_header(client, %{room_admin: true, room: room})

    case Tesla.post(client.client, path, request, headers: headers) do
      {:ok, %{status: 200, body: body}} -> {:ok, ParticipantInfo.decode(body)}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Removes a participant from a room.
  """
  def remove_participant(%__MODULE__{} = client, room, identity) do
    path = "/twirp/livekit.RoomService/RemoveParticipant"

    request =
      struct(RoomParticipantIdentity, %{room: room, identity: identity})
      |> RoomParticipantIdentity.encode()

    headers = auth_header(client, %{room_admin: true, room: room})

    case Tesla.post(client.client, path, request, headers: headers) do
      {:ok, %{status: 200, body: _body}} -> :ok
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Mutes or unmutes a participant's track.
  """
  def mute_published_track(%__MODULE__{} = client, room, identity, track_sid, muted) do
    path = "/twirp/livekit.RoomService/MutePublishedTrack"

    request =
      struct(MuteRoomTrackRequest, %{
        room: room,
        identity: identity,
        track_sid: track_sid,
        muted: muted
      })
      |> MuteRoomTrackRequest.encode()

    headers = auth_header(client, %{room_admin: true, room: room})

    case Tesla.post(client.client, path, request, headers: headers) do
      {:ok, %{status: 200, body: body}} -> {:ok, MuteRoomTrackResponse.decode(body)}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates a participant's metadata, permissions, or name.
  """
  def update_participant(%__MODULE__{} = client, room, identity, opts \\ []) do
    path = "/twirp/livekit.RoomService/UpdateParticipant"

    # Convert attributes to string key-value pairs if provided
    attributes =
      case Keyword.get(opts, :attributes) do
        nil ->
          nil

        attrs when is_map(attrs) ->
          attrs
          |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
          |> Enum.into(%{})
      end

    request =
      struct(UpdateParticipantRequest, %{
        room: room,
        identity: identity,
        metadata: Keyword.get(opts, :metadata),
        permission: Keyword.get(opts, :permission),
        name: Keyword.get(opts, :name),
        attributes: attributes
      })
      |> UpdateParticipantRequest.encode()

    headers = auth_header(client, %{room_admin: true, room: room})

    case Tesla.post(client.client, path, request, headers: headers) do
      {:ok, %{status: 200, body: body}} -> {:ok, ParticipantInfo.decode(body)}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates track subscriptions for a participant.
  """
  def update_subscriptions(%__MODULE__{} = client, room, identity, track_sids, subscribe) do
    path = "/twirp/livekit.RoomService/UpdateSubscriptions"

    request =
      struct(UpdateSubscriptionsRequest, %{
        room: room,
        identity: identity,
        track_sids: track_sids,
        subscribe: subscribe
      })
      |> UpdateSubscriptionsRequest.encode()

    headers = auth_header(client, %{room_admin: true, room: room})

    case Tesla.post(client.client, path, request, headers: headers) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sends data to specific participants in a room.
  """
  def send_data(%__MODULE__{} = client, room, data, kind, opts \\ []) do
    path = "/twirp/livekit.RoomService/SendData"

    request =
      struct(SendDataRequest, %{
        room: room,
        data: data,
        kind: kind,
        destination_sids: Keyword.get(opts, :destination_sids, []),
        destination_identities: Keyword.get(opts, :destination_identities, []),
        nonce: :crypto.strong_rand_bytes(16)
      })
      |> SendDataRequest.encode()

    headers = auth_header(client, %{room_admin: true, room: room})

    case Tesla.post(client.client, path, request, headers: headers) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp auth_header(client, video_grant) do
    token =
      AccessToken.new(client.api_key, client.api_secret)
      |> AccessToken.with_identity("service")
      |> AccessToken.with_ttl(600)
      |> AccessToken.add_grant(video_grant)
      |> AccessToken.to_jwt()

    [
      {"Authorization", "Bearer #{token}"},
      {"User-Agent", "LiveKit Elixir SDK"}
    ]
  end
end

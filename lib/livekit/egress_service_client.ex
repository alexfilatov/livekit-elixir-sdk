defmodule Livekit.EgressServiceClient do
  @moduledoc """
  Client for the LiveKit Egress service — recording a room to storage, or
  streaming it out over RTMP/SRT.

  ## Transport

  Egress speaks Twirp over HTTP, exactly as `Livekit.RoomServiceClient` does:
  a protobuf body POSTed to `/twirp/livekit.Egress/<Method>`, authorized by a
  signed access token.

  This client used to dial gRPC on the LiveKit URL's port and send
  `authorization: Bearer <key>:<secret>`. Neither is what a LiveKit server
  offers: `livekit-server` and LiveKit Cloud expose Egress over Twirp on the
  ordinary HTTPS port, and the credential must be a JWT carrying the
  `roomRecord` grant. Every call through the old client failed before it
  reached the service.

  ## Authorization

  Every method mints a short-lived token with `room_record: true`. The
  credential never leaves the server that holds the API secret, so an egress
  cannot be started by a participant holding a join token.

  ## Example

      client = Livekit.EgressServiceClient.new(
        "wss://my-project.livekit.cloud", api_key, api_secret
      )

      {:ok, info} =
        Livekit.EgressServiceClient.start_room_composite_egress(client, %Livekit.RoomCompositeEgressRequest{
          room_name: "my-room",
          layout: "grid",
          stream_outputs: [
            %Livekit.StreamOutput{protocol: :RTMP, urls: ["rtmp://a.rtmp.youtube.com/live2/KEY"]}
          ],
          options: {:preset, :H264_720P_30}
        })

      info.egress_id
      #=> "EG_xxxxxxxx"

  `info.status` moves `EGRESS_STARTING -> EGRESS_ACTIVE -> EGRESS_COMPLETE`,
  and `info.stream_results` reports each destination separately, so one
  rejected stream key can be told apart from a failed egress.

  Stream URLs come back with their key masked (`rtmp://host/live/{ab...yz}`),
  so an `EgressInfo` is safe to log.
  """

  alias Livekit.AccessToken

  require Logger

  defstruct [:base_url, :api_key, :api_secret, :client]

  @type t :: %__MODULE__{
          base_url: String.t(),
          api_key: String.t(),
          api_secret: String.t(),
          client: Tesla.Client.t()
        }

  @service "/twirp/livekit.Egress"

  @doc """
  Creates a new EgressServiceClient.

  Accepts the same URL as the rest of the SDK — `ws://`/`wss://` is rewritten
  to `http://`/`https://`, so a `LIVEKIT_URL` can be passed through unchanged.
  """
  @spec new(String.t(), String.t(), String.t()) :: t()
  def new(base_url, api_key, api_secret) do
    base_url =
      base_url
      |> String.replace(~r{^ws://}, "http://")
      |> String.replace(~r{^wss://}, "https://")

    middleware = [
      {Tesla.Middleware.BaseUrl, base_url},
      {Tesla.Middleware.Headers,
       [
         {"content-type", "application/protobuf"},
         {"accept", "application/protobuf"}
       ]},
      {Tesla.Middleware.Logger,
       [
         debug: false,
         filter_headers: ["authorization"],
         formatter: fn env, _opts -> "#{env.method} #{env.url} -> #{env.status}" end
       ]}
    ]

    %__MODULE__{
      base_url: base_url,
      api_key: api_key,
      api_secret: api_secret,
      client: Tesla.client(middleware, Livekit.HTTP.adapter(30_000))
    }
  end

  @doc """
  Starts an egress that composites a whole room into one output.

  This is the one to use for "stream this session to YouTube": pass
  `stream_outputs` and the room is encoded once and pushed to every URL.
  """
  @spec start_room_composite_egress(t(), Livekit.RoomCompositeEgressRequest.t()) ::
          {:ok, Livekit.EgressInfo.t()} | {:error, term()}
  def start_room_composite_egress(
        %__MODULE__{} = client,
        %Livekit.RoomCompositeEgressRequest{} = request
      ) do
    call(
      client,
      "StartRoomCompositeEgress",
      Livekit.RoomCompositeEgressRequest,
      request,
      Livekit.EgressInfo
    )
  end

  @doc """
  Starts an egress that renders an arbitrary web page.
  """
  @spec start_web_egress(t(), Livekit.WebEgressRequest.t()) ::
          {:ok, Livekit.EgressInfo.t()} | {:error, term()}
  def start_web_egress(%__MODULE__{} = client, %Livekit.WebEgressRequest{} = request) do
    call(client, "StartWebEgress", Livekit.WebEgressRequest, request, Livekit.EgressInfo)
  end

  @doc """
  Starts an egress of a single participant's tracks.
  """
  @spec start_participant_egress(t(), Livekit.ParticipantEgressRequest.t()) ::
          {:ok, Livekit.EgressInfo.t()} | {:error, term()}
  def start_participant_egress(
        %__MODULE__{} = client,
        %Livekit.ParticipantEgressRequest{} = request
      ) do
    call(
      client,
      "StartParticipantEgress",
      Livekit.ParticipantEgressRequest,
      request,
      Livekit.EgressInfo
    )
  end

  @doc """
  Starts an egress compositing specific audio and video tracks.
  """
  @spec start_track_composite_egress(t(), Livekit.TrackCompositeEgressRequest.t()) ::
          {:ok, Livekit.EgressInfo.t()} | {:error, term()}
  def start_track_composite_egress(
        %__MODULE__{} = client,
        %Livekit.TrackCompositeEgressRequest{} = request
      ) do
    call(
      client,
      "StartTrackCompositeEgress",
      Livekit.TrackCompositeEgressRequest,
      request,
      Livekit.EgressInfo
    )
  end

  @doc """
  Starts an egress of a single track, without transcoding.
  """
  @spec start_track_egress(t(), Livekit.TrackEgressRequest.t()) ::
          {:ok, Livekit.EgressInfo.t()} | {:error, term()}
  def start_track_egress(%__MODULE__{} = client, %Livekit.TrackEgressRequest{} = request) do
    call(client, "StartTrackEgress", Livekit.TrackEgressRequest, request, Livekit.EgressInfo)
  end

  @doc """
  Changes the layout of a running room composite egress.
  """
  @spec update_layout(t(), Livekit.UpdateLayoutRequest.t()) ::
          {:ok, Livekit.EgressInfo.t()} | {:error, term()}
  def update_layout(%__MODULE__{} = client, %Livekit.UpdateLayoutRequest{} = request) do
    call(client, "UpdateLayout", Livekit.UpdateLayoutRequest, request, Livekit.EgressInfo)
  end

  @doc """
  Adds or removes stream URLs on a running egress.

  This is how a second destination is added mid-broadcast, and how one
  destination is dropped without stopping the others.
  """
  @spec update_stream(t(), Livekit.UpdateStreamRequest.t()) ::
          {:ok, Livekit.EgressInfo.t()} | {:error, term()}
  def update_stream(%__MODULE__{} = client, %Livekit.UpdateStreamRequest{} = request) do
    call(client, "UpdateStream", Livekit.UpdateStreamRequest, request, Livekit.EgressInfo)
  end

  @doc """
  Lists egress operations.

  Narrow it with `room_name`, `egress_id`, or `active: true`; the default
  request lists everything the project has.
  """
  @spec list_egress(t(), Livekit.ListEgressRequest.t()) ::
          {:ok, Livekit.ListEgressResponse.t()} | {:error, term()}
  def list_egress(%__MODULE__{} = client, request \\ %Livekit.ListEgressRequest{}) do
    call(client, "ListEgress", Livekit.ListEgressRequest, request, Livekit.ListEgressResponse)
  end

  @doc """
  Stops a running egress.
  """
  @spec stop_egress(t(), Livekit.StopEgressRequest.t()) ::
          {:ok, Livekit.EgressInfo.t()} | {:error, term()}
  def stop_egress(%__MODULE__{} = client, %Livekit.StopEgressRequest{} = request) do
    call(client, "StopEgress", Livekit.StopEgressRequest, request, Livekit.EgressInfo)
  end

  # Private functions

  defp call(client, method, request_module, request, response_module) do
    body = request_module.encode(request)

    case Tesla.post(client.client, "#{@service}/#{method}", body, headers: auth_header(client)) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, response_module.decode(response)}

      {:ok, %{status: status, body: response}} ->
        Logger.error("#{method} failed with status #{status}: #{inspect(response)}")
        {:error, {status, response}}

      {:error, reason} ->
        Logger.error("#{method} request error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp auth_header(client) do
    token =
      AccessToken.new(client.api_key, client.api_secret)
      |> AccessToken.with_identity("service")
      |> AccessToken.with_ttl(600)
      |> AccessToken.add_grant(Livekit.Grants.room_record())
      |> AccessToken.to_jwt()

    [
      {"authorization", "Bearer #{token}"},
      {"user-agent", "Livekit Elixir SDK"}
    ]
  end
end

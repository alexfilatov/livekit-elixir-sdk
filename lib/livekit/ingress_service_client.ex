defmodule Livekit.IngressServiceClient do
  @moduledoc """
  Client for the LiveKit Ingress service — pulling an external RTMP, WHIP or
  URL source *into* a room.

  ## Transport

  Like `Livekit.RoomServiceClient` and `Livekit.EgressServiceClient`, this
  speaks Twirp: a protobuf body POSTed to `/twirp/livekit.Ingress/<Method>`,
  authorized by a token carrying the `ingressAdmin` grant.

  It previously dialled gRPC and sent `authorization: Bearer <key>:<secret>`.
  A LiveKit server offers neither, so no call through the old client ever
  reached the service.

  ## Example

      client = Livekit.IngressServiceClient.new(url, api_key, api_secret)

      {:ok, info} =
        Livekit.IngressServiceClient.create_ingress(client, %Livekit.CreateIngressRequest{
          input_type: :RTMP_INPUT,
          name: "my-stream",
          room_name: "my-room",
          participant_identity: "streamer"
        })

      info.url          #=> the RTMP endpoint to publish to
      info.stream_key   #=> the key for it
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

  @service "/twirp/livekit.Ingress"

  @doc """
  Creates a new IngressServiceClient.
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
  Creates an ingress endpoint.
  """
  @spec create_ingress(t(), Livekit.CreateIngressRequest.t()) ::
          {:ok, Livekit.IngressInfo.t()} | {:error, term()}
  def create_ingress(%__MODULE__{} = client, %Livekit.CreateIngressRequest{} = request) do
    call(client, "CreateIngress", Livekit.CreateIngressRequest, request, Livekit.IngressInfo)
  end

  @doc """
  Updates an existing ingress endpoint.
  """
  @spec update_ingress(t(), Livekit.UpdateIngressRequest.t()) ::
          {:ok, Livekit.IngressInfo.t()} | {:error, term()}
  def update_ingress(%__MODULE__{} = client, %Livekit.UpdateIngressRequest{} = request) do
    call(client, "UpdateIngress", Livekit.UpdateIngressRequest, request, Livekit.IngressInfo)
  end

  @doc """
  Lists ingress endpoints.
  """
  @spec list_ingress(t(), Livekit.ListIngressRequest.t()) ::
          {:ok, Livekit.ListIngressResponse.t()} | {:error, term()}
  def list_ingress(%__MODULE__{} = client, request \\ %Livekit.ListIngressRequest{}) do
    call(client, "ListIngress", Livekit.ListIngressRequest, request, Livekit.ListIngressResponse)
  end

  @doc """
  Deletes an ingress endpoint.
  """
  @spec delete_ingress(t(), Livekit.DeleteIngressRequest.t()) ::
          {:ok, Livekit.IngressInfo.t()} | {:error, term()}
  def delete_ingress(%__MODULE__{} = client, %Livekit.DeleteIngressRequest{} = request) do
    call(client, "DeleteIngress", Livekit.DeleteIngressRequest, request, Livekit.IngressInfo)
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
      |> AccessToken.add_grant(Livekit.Grants.ingress_admin())
      |> AccessToken.to_jwt()

    [
      {"authorization", "Bearer #{token}"},
      {"user-agent", "Livekit Elixir SDK"}
    ]
  end
end

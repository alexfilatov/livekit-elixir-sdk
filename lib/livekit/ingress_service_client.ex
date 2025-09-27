defmodule Livekit.IngressServiceClient do
  @moduledoc """
  Client for interacting with the LiveKit Ingress service.

  The Ingress service enables bringing external streams into LiveKit rooms,
  including RTMP streams, WebRTC ingress, and file-based input sources.
  """

  alias Livekit.{AccessToken, Grants, Ingress}

  require Logger

  @doc """
  Creates a new IngressServiceClient.

  ## Parameters

  - `url` - The LiveKit server URL (can be ws:// or wss://, will be converted to appropriate format)
  - `api_key` - The API key for authentication
  - `api_secret` - The API secret for authentication

  ## Returns

  - `{:ok, client}` - On successful connection
  - `{:error, reason}` - On connection failure

  ## Examples

      iex> {:ok, client} = Livekit.IngressServiceClient.new("wss://my-livekit.com", "api_key", "secret")
      {:ok, {#PID<0.123.0>, %{}}}
  """
  def new(url, api_key, api_secret)
      when is_binary(url) and is_binary(api_key) and is_binary(api_secret) do
    # Convert ws:// to http:// and wss:// to https:// for gRPC
    grpc_url =
      url
      |> String.replace(~r{^ws://}, "http://")
      |> String.replace(~r{^wss://}, "https://")

    uri = URI.parse(grpc_url)
    host = uri.host || grpc_url
    port = uri.port || if uri.scheme == "https", do: 443, else: 80

    # Generate JWT token with ingress_admin grants
    token =
      AccessToken.new(api_key, api_secret)
      |> AccessToken.with_identity("ingress_service")
      |> AccessToken.with_grants(Grants.ingress_admin())
      |> AccessToken.to_jwt()

    # Set up auth headers
    metadata = %{
      "authorization" => "Bearer #{token}"
    }

    # Connect with SSL if https
    opts =
      if uri.scheme == "https" do
        [cred: GRPC.Credential.new(ssl: [])]
      else
        []
      end

    case GRPC.Stub.connect("#{host}:#{port}", opts) do
      {:ok, channel} ->
        Logger.info("Connected to LiveKit Ingress service at #{host}:#{port}")
        {:ok, {channel, metadata}}

      {:error, reason} ->
        Logger.error("Failed to connect to LiveKit Ingress service: #{inspect(reason)}")
        {:error, "Failed to connect to LiveKit server: #{inspect(reason)}"}
    end
  end

  @doc """
  Creates a new ingress endpoint.

  ## Parameters

  - `client` - The client connection tuple returned from `new/3`
  - `request` - A CreateIngressRequest struct

  ## Returns

  - `{:ok, ingress_info}` - On success, returns an IngressInfo struct
  - `{:error, reason}` - On failure

  ## Examples

      request = %Livekit.CreateIngressRequest{
        input_type: :RTMP_INPUT,
        name: "my-stream",
        room_name: "my-room",
        participant_identity: "streamer"
      }
      {:ok, ingress} = Livekit.IngressServiceClient.create_ingress(client, request)
  """
  def create_ingress({channel, metadata}, %Livekit.CreateIngressRequest{} = request) do
    case Ingress.Stub.create_ingress(channel, request, metadata) do
      {:ok, %Livekit.IngressInfo{} = ingress_info} ->
        Logger.info("Created ingress: #{ingress_info.ingress_id}")
        {:ok, ingress_info}

      {:error, %GRPC.RPCError{} = error} ->
        Logger.error("Failed to create ingress: #{error.message}")
        {:error, error.message}

      {:error, reason} ->
        Logger.error("Failed to create ingress: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Updates an existing ingress endpoint.

  Note: Ingress can only be updated when it's in ENDPOINT_INACTIVE state.

  ## Parameters

  - `client` - The client connection tuple returned from `new/3`
  - `request` - An UpdateIngressRequest struct

  ## Returns

  - `{:ok, ingress_info}` - On success, returns an updated IngressInfo struct
  - `{:error, reason}` - On failure
  """
  def update_ingress({channel, metadata}, %Livekit.UpdateIngressRequest{} = request) do
    case Ingress.Stub.update_ingress(channel, request, metadata) do
      {:ok, %Livekit.IngressInfo{} = ingress_info} ->
        Logger.info("Updated ingress: #{ingress_info.ingress_id}")
        {:ok, ingress_info}

      {:error, %GRPC.RPCError{} = error} ->
        Logger.error("Failed to update ingress: #{error.message}")
        {:error, error.message}

      {:error, reason} ->
        Logger.error("Failed to update ingress: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Lists ingress endpoints.

  ## Parameters

  - `client` - The client connection tuple returned from `new/3`
  - `request` - A ListIngressRequest struct (optional, defaults to empty request)

  ## Returns

  - `{:ok, list_response}` - On success, returns a ListIngressResponse struct
  - `{:error, reason}` - On failure

  ## Examples

      # List all ingress endpoints
      {:ok, response} = Livekit.IngressServiceClient.list_ingress(client)

      # Filter by room name
      request = %Livekit.ListIngressRequest{room_name: "my-room"}
      {:ok, response} = Livekit.IngressServiceClient.list_ingress(client, request)
  """
  def list_ingress({channel, metadata}, request \\ %Livekit.ListIngressRequest{}) do
    case Ingress.Stub.list_ingress(channel, request, metadata) do
      {:ok, %Livekit.ListIngressResponse{} = response} ->
        Logger.info("Listed #{length(response.items)} ingress endpoints")
        {:ok, response}

      {:error, %GRPC.RPCError{} = error} ->
        Logger.error("Failed to list ingress: #{error.message}")
        {:error, error.message}

      {:error, reason} ->
        Logger.error("Failed to list ingress: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Deletes an ingress endpoint.

  ## Parameters

  - `client` - The client connection tuple returned from `new/3`
  - `request` - A DeleteIngressRequest struct

  ## Returns

  - `{:ok, ingress_info}` - On success, returns the deleted IngressInfo struct
  - `{:error, reason}` - On failure

  ## Examples

      request = %Livekit.DeleteIngressRequest{ingress_id: "ingress_123"}
      {:ok, ingress} = Livekit.IngressServiceClient.delete_ingress(client, request)
  """
  def delete_ingress({channel, metadata}, %Livekit.DeleteIngressRequest{} = request) do
    case Ingress.Stub.delete_ingress(channel, request, metadata) do
      {:ok, %Livekit.IngressInfo{} = ingress_info} ->
        Logger.info("Deleted ingress: #{ingress_info.ingress_id}")
        {:ok, ingress_info}

      {:error, %GRPC.RPCError{} = error} ->
        Logger.error("Failed to delete ingress: #{error.message}")
        {:error, error.message}

      {:error, reason} ->
        Logger.error("Failed to delete ingress: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

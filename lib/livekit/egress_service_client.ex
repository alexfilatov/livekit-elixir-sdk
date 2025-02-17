defmodule LiveKit.EgressServiceClient do
  @moduledoc """
  Client for interacting with the LiveKit Egress service.
  """

  alias Livekit.Egress

  @doc """
  Creates a new EgressServiceClient.
  """
  def new(url, api_key, api_secret) when is_binary(url) do
    uri = URI.parse(url)
    host = uri.host || url
    port = uri.port || 443

    # Set up auth headers
    metadata = %{
      "authorization" => "Bearer #{api_key}:#{api_secret}"
    }

    # Connect with SSL if https
    opts =
      if uri.scheme == "https" do
        [cred: GRPC.Credential.new(ssl: true)]
      else
        []
      end

    case GRPC.Stub.connect("#{host}:#{port}", opts) do
      {:ok, channel} -> {:ok, {channel, metadata}}
      {:error, reason} -> {:error, "Failed to connect to LiveKit server: #{inspect(reason)}"}
    end
  end

  @doc """
  Lists all egress operations.
  """
  def list_egress({channel, metadata}, request \\ %Livekit.ListEgressRequest{}) do
    Egress.Stub.list_egress(channel, request, metadata: metadata)
  end

  @doc """
  Starts a room composite egress.
  """
  def start_room_composite_egress({channel, metadata}, request) do
    Egress.Stub.start_room_composite_egress(channel, request, metadata: metadata)
  end

  @doc """
  Starts a track egress.
  """
  def start_track_egress({channel, metadata}, request) do
    Egress.Stub.start_track_egress(channel, request, metadata: metadata)
  end

  @doc """
  Stops an egress operation.
  """
  def stop_egress({channel, metadata}, request) do
    Egress.Stub.stop_egress(channel, request, metadata: metadata)
  end
end

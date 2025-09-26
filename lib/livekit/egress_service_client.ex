defmodule Livekit.EgressServiceClient do
  @moduledoc """
  Client for interacting with the Livekit Egress service.
  """

  alias Livekit.Egress

  
  
  @doc """
  Create a new EgressServiceClient by connecting to a Livekit Egress server and preparing authorization metadata.
  
  ## Parameters
  
    - url: The server URL or host (e.g., "https://egress.livekit.example:443" or "egress.livekit.example").
    - api_key: API key used to build the authorization header.
    - api_secret: API secret used to build the authorization header.
  
  ## Returns
  
    - `{:ok, {channel, metadata}}` where `channel` is a `GRPC.Channel.t()` connected to the server and `metadata` is a map containing the `"authorization"` header.
    - `{:error, reason}` where `reason` is an error message string describing the failure.
  """
  @spec new(url :: binary(), api_key :: binary(), api_secret :: binary()) ::
            {:ok, {GRPC.Channel.t(), metadata :: map()}} | {:error, String.t()}
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
        [cred: GRPC.Credential.new(ssl: [])]
      else
        []
      end

    case GRPC.Stub.connect("#{host}:#{port}", opts) do
      {:ok, channel} -> {:ok, {channel, metadata}}
      {:error, reason} -> {:error, "Failed to connect to Livekit server: #{inspect(reason)}"}
    end
  end

  @doc """
  Lists all egress operations.
  """
  def list_egress({channel, metadata}, request \\ %Livekit.ListEgressRequest{}) do
    Egress.Stub.list_egress(channel, request, metadata)
  end

  @doc """
  Starts a room composite egress.
  """
  def start_room_composite_egress({channel, metadata}, request) do
    Egress.Stub.start_room_composite_egress(channel, request, metadata)
  end

  @doc """
  Starts a track egress.
  """
  def start_track_egress({channel, metadata}, request) do
    Egress.Stub.start_track_egress(channel, request, metadata)
  end

  @doc """
  Stops an egress operation.
  """
  def stop_egress({channel, metadata}, request) do
    Egress.Stub.stop_egress(channel, request, metadata)
  end
end

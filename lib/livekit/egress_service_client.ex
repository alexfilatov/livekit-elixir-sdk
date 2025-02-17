defmodule LiveKit.EgressServiceClient do
  @moduledoc """
  Client for interacting with the LiveKit Egress service.
  """

  alias Livekit.Egress

  @doc """
  Creates a new EgressServiceClient.
  """
  def new(host, port, opts \\ []) do
    {:ok, channel} = GRPC.Stub.connect("#{host}:#{port}", opts)
    channel
  end

  @doc """
  Lists all egress operations.
  """
  def list_egress(channel, request \\ %Livekit.ListEgressRequest{}) do
    Egress.Stub.list_egress(channel, request)
  end

  @doc """
  Starts a room composite egress.
  """
  def start_room_composite_egress(channel, request) do
    Egress.Stub.start_room_composite_egress(channel, request)
  end

  @doc """
  Starts a track egress.
  """
  def start_track_egress(channel, request) do
    Egress.Stub.start_track_egress(channel, request)
  end

  @doc """
  Stops an egress operation.
  """
  def stop_egress(channel, request) do
    Egress.Stub.stop_egress(channel, request)
  end
end

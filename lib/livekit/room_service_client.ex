defmodule LiveKit.RoomServiceClient do
  @moduledoc """
  Client for interacting with LiveKit room services.
  """

  use Tesla

  alias LiveKit.Utils

  plug(Tesla.Middleware.BaseUrl, "")
  plug(Tesla.Middleware.JSON)

  defstruct api_key: nil,
            api_secret: nil,
            base_url: nil,
            client: nil

  @type t :: %__MODULE__{
          api_key: String.t() | nil,
          api_secret: String.t() | nil,
          base_url: String.t() | nil,
          client: Tesla.Client.t() | nil
        }

  @doc """
  Creates a new RoomServiceClient instance.
  """
  def new(base_url, api_key, api_secret) do
    middleware = [
      {Tesla.Middleware.BaseUrl, Utils.to_http_url(base_url)},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Opts, [adapter: [recv_timeout: 5000]]}
    ]

    client = Tesla.client(middleware)

    %__MODULE__{
      base_url: Utils.to_http_url(base_url),
      api_key: api_key,
      api_secret: api_secret,
      client: client
    }
  end

  @doc """
  Creates a new room with the specified options.
  """
  def create_room(%__MODULE__{} = client, name, opts \\ []) do
    params = Enum.into(opts, %{name: name})
    path = "/twirp/livekit.proto.RoomService/CreateRoom"

    case do_request(client, :post, path, params) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists all active rooms.
  """
  def list_rooms(%__MODULE__{} = client) do
    path = "/twirp/livekit.proto.RoomService/ListRooms"

    case do_request(client, :get, path) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes a room by name.
  """
  def delete_room(%__MODULE__{} = client, room) do
    path = "/twirp/livekit.proto.RoomService/DeleteRoom"

    case do_request(client, :post, path, %{room: room}) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_request(client, method, path, body \\ nil) do
    headers = auth_header(client, method |> to_string |> String.upcase(), path)

    case apply(Tesla, method, [client.client, path] ++ request_args(body, headers)) do
      {:ok, %{status: status}} when status != 200 ->
        {:error, :request_failed}

      {:ok, response} ->
        {:ok, response.body}

      {:error, :econnrefused} ->
        {:error, :connection_refused}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_args(nil, headers), do: [[headers: headers]]
  defp request_args(body, headers), do: [body, [headers: headers]]

  defp auth_header(client, method, path) do
    timestamp = System.system_time(:second)
    nonce = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

    signature =
      [client.api_key, timestamp, nonce, method, path]
      |> Enum.join(" ")
      |> then(&:crypto.mac(:hmac, :sha256, client.api_secret, &1))
      |> Base.encode16(case: :lower)

    [
      {"Authorization", "Bearer #{signature}"},
      {"X-API-Key", client.api_key},
      {"X-API-Nonce", nonce},
      {"X-API-Timestamp", to_string(timestamp)}
    ]
  end
end

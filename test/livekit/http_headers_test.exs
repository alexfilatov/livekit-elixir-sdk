defmodule Livekit.HTTPHeadersTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Header names must be lowercase.

  Tesla's header lookup is case-sensitive, and `Tesla.Adapter.Httpc` — the
  SDK's default adapter — pulls the request's content type with
  `Tesla.get_header(env, "content-type")`. A header written as
  `{"Content-Type", ...}` is therefore never found, httpc sends an empty
  content type, and the server rejects the request for a reason that names
  neither the header nor the adapter.

  This shipped: LiveKit's Twirp endpoint answered `bad_route: unexpected
  Content-Type: ""` and every room creation failed. Hackney had been passing
  the header through verbatim, so the bug only appeared when the default
  adapter changed.
  """

  @tesla_header_regex ~r/\{"([A-Za-z][A-Za-z0-9-]*)",/

  test "no module sets a Tesla header with an uppercase name" do
    offenders =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> then(&Regex.scan(@tesla_header_regex, &1, capture: :all_but_first))
        |> List.flatten()
        |> Enum.filter(&header_name?/1)
        |> Enum.filter(&(&1 != String.downcase(&1)))
        |> Enum.map(&{path, &1})
      end)

    assert offenders == [],
           "uppercase Tesla header names (httpc will not find these): #{inspect(offenders)}"
  end

  # Only the names that actually matter as HTTP headers; the codebase is full
  # of ordinary two-tuples whose first element happens to be a string.
  defp header_name?(name) do
    String.downcase(name) in [
      "content-type",
      "accept",
      "authorization",
      "user-agent",
      "xi-api-key"
    ]
  end

  test "the room service client sends a content type httpc can find" do
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "POST", "/twirp/livekit.RoomService/CreateRoom", fn conn ->
      # What the server actually receives. Empty here is the failure that
      # took every room creation down.
      assert [content_type] = Plug.Conn.get_req_header(conn, "content-type")
      assert content_type =~ "application/protobuf"

      conn
      |> Plug.Conn.put_resp_content_type("application/protobuf")
      |> Plug.Conn.resp(200, Livekit.Room.encode(%Livekit.Room{name: "r", sid: "RM_1"}))
    end)

    client =
      Livekit.RoomServiceClient.new(
        "http://localhost:#{bypass.port}",
        "key",
        "secret-at-least-32-bytes-long-ok!!"
      )

    assert {:ok, %Livekit.Room{}} = Livekit.RoomServiceClient.create_room(client, "r")
  end
end

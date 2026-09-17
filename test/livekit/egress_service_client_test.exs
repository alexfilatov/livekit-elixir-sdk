defmodule Livekit.EgressServiceClientTest do
  @moduledoc """
  The egress client used to dial gRPC with `Bearer <key>:<secret>`. A LiveKit
  server offers Twirp and wants a JWT carrying `roomRecord`, so these tests
  assert the things that were wrong: the path, the credential, and that a
  reply decodes.
  """

  use ExUnit.Case, async: true

  alias Livekit.EgressServiceClient

  @api_key "api_key_123"
  @api_secret "secret_456"

  setup do
    bypass = Bypass.open()
    client = EgressServiceClient.new("http://localhost:#{bypass.port}", @api_key, @api_secret)
    {:ok, bypass: bypass, client: client}
  end

  describe "new/3" do
    test "keeps an http URL" do
      client = EgressServiceClient.new("http://example.com", @api_key, @api_secret)
      assert client.base_url == "http://example.com"
    end

    test "converts ws:// to http://" do
      assert EgressServiceClient.new("ws://example.com", @api_key, @api_secret).base_url ==
               "http://example.com"
    end

    test "converts wss:// to https://, so a LIVEKIT_URL passes through unchanged" do
      assert EgressServiceClient.new("wss://x.livekit.cloud", @api_key, @api_secret).base_url ==
               "https://x.livekit.cloud"
    end
  end

  describe "authorization" do
    test "sends a signed JWT, not the api key and secret", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/twirp/livekit.Egress/ListEgress", fn conn ->
        ["Bearer " <> token] = Plug.Conn.get_req_header(conn, "authorization")

        refute token =~ @api_secret
        assert {:ok, claims} = Livekit.AccessToken.verify(token, @api_key, @api_secret)

        # roomRecord is the grant Egress checks; without it the call is refused.
        assert claims["video"]["roomRecord"] == true

        respond(conn, Livekit.ListEgressResponse, %Livekit.ListEgressResponse{})
      end)

      assert {:ok, _} = EgressServiceClient.list_egress(client)
    end

    test "sends protobuf content type", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, fn conn ->
        assert Plug.Conn.get_req_header(conn, "content-type") == ["application/protobuf"]
        respond(conn, Livekit.ListEgressResponse, %Livekit.ListEgressResponse{})
      end)

      assert {:ok, _} = EgressServiceClient.list_egress(client)
    end
  end

  describe "start_room_composite_egress/2" do
    test "posts to the Twirp path and returns the decoded EgressInfo", %{
      bypass: bypass,
      client: client
    } do
      Bypass.expect_once(
        bypass,
        "POST",
        "/twirp/livekit.Egress/StartRoomCompositeEgress",
        fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          request = Livekit.RoomCompositeEgressRequest.decode(body)

          assert request.room_name == "session_42"

          assert [%Livekit.StreamOutput{protocol: :RTMP, urls: [url]}] = request.stream_outputs
          assert url == "rtmp://a.rtmp.youtube.com/live2/key"

          respond(conn, Livekit.EgressInfo, %Livekit.EgressInfo{
            egress_id: "EG_abc",
            room_name: "session_42",
            status: :EGRESS_STARTING
          })
        end
      )

      request = %Livekit.RoomCompositeEgressRequest{
        room_name: "session_42",
        layout: "grid",
        stream_outputs: [
          %Livekit.StreamOutput{
            protocol: :RTMP,
            urls: ["rtmp://a.rtmp.youtube.com/live2/key"]
          }
        ]
      }

      assert {:ok, info} = EgressServiceClient.start_room_composite_egress(client, request)
      assert info.egress_id == "EG_abc"
      assert info.status == :EGRESS_STARTING
    end

    test "surfaces a Twirp error as {:error, {status, body}}", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, ~s({"code":"not_found","msg":"requested room does not exist"}))
      end)

      request = %Livekit.RoomCompositeEgressRequest{room_name: "nope"}

      assert {:error, {404, body}} =
               EgressServiceClient.start_room_composite_egress(client, request)

      assert body =~ "requested room does not exist"
    end
  end

  describe "stop_egress/2" do
    test "posts the egress id", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/twirp/livekit.Egress/StopEgress", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Livekit.StopEgressRequest.decode(body).egress_id == "EG_abc"

        respond(conn, Livekit.EgressInfo, %Livekit.EgressInfo{
          egress_id: "EG_abc",
          status: :EGRESS_ENDING
        })
      end)

      request = %Livekit.StopEgressRequest{egress_id: "EG_abc"}
      assert {:ok, info} = EgressServiceClient.stop_egress(client, request)
      assert info.status == :EGRESS_ENDING
    end
  end

  describe "list_egress/2" do
    test "decodes per-destination results, so a rejected key is distinguishable", %{
      bypass: bypass,
      client: client
    } do
      Bypass.expect_once(bypass, "POST", "/twirp/livekit.Egress/ListEgress", fn conn ->
        respond(conn, Livekit.ListEgressResponse, %Livekit.ListEgressResponse{
          items: [
            %Livekit.EgressInfo{
              egress_id: "EG_abc",
              status: :EGRESS_ACTIVE,
              stream_results: [
                %Livekit.StreamInfo{url: "rtmp://youtube/{ab...yz}", status: :ACTIVE},
                %Livekit.StreamInfo{
                  url: "rtmp://facebook/{cd...wx}",
                  status: :FAILED,
                  error: "connection refused"
                }
              ]
            }
          ]
        })
      end)

      assert {:ok, %Livekit.ListEgressResponse{items: [info]}} =
               EgressServiceClient.list_egress(client)

      assert [youtube, facebook] = info.stream_results
      assert youtube.status == :ACTIVE
      assert facebook.status == :FAILED
      assert facebook.error == "connection refused"
    end
  end

  describe "update_stream/2" do
    test "adds a destination to a running egress", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/twirp/livekit.Egress/UpdateStream", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Livekit.UpdateStreamRequest.decode(body)

        assert request.egress_id == "EG_abc"
        assert request.add_output_urls == ["rtmp://second/destination"]

        respond(conn, Livekit.EgressInfo, %Livekit.EgressInfo{egress_id: "EG_abc"})
      end)

      request = %Livekit.UpdateStreamRequest{
        egress_id: "EG_abc",
        add_output_urls: ["rtmp://second/destination"]
      }

      assert {:ok, _} = EgressServiceClient.update_stream(client, request)
    end
  end

  defp respond(conn, module, message) do
    conn
    |> Plug.Conn.put_resp_content_type("application/protobuf")
    |> Plug.Conn.resp(200, module.encode(message))
  end
end

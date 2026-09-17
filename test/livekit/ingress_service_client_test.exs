defmodule Livekit.IngressServiceClientTest do
  @moduledoc """
  These tests used to mock `GRPC.Stub`, which meant they passed while no call
  could reach a real server: LiveKit serves Ingress over Twirp, not gRPC. They
  now exercise the transport that is actually used.
  """

  use ExUnit.Case, async: true

  alias Livekit.IngressServiceClient

  @api_key "api_key_123"
  @api_secret "secret_456"

  setup do
    bypass = Bypass.open()
    client = IngressServiceClient.new("http://localhost:#{bypass.port}", @api_key, @api_secret)
    {:ok, bypass: bypass, client: client}
  end

  describe "new/3" do
    test "keeps an http URL" do
      assert IngressServiceClient.new("http://example.com", @api_key, @api_secret).base_url ==
               "http://example.com"
    end

    test "converts wss:// to https://" do
      assert IngressServiceClient.new("wss://x.livekit.cloud", @api_key, @api_secret).base_url ==
               "https://x.livekit.cloud"
    end
  end

  describe "authorization" do
    test "sends a JWT carrying ingressAdmin, not the raw secret", %{
      bypass: bypass,
      client: client
    } do
      Bypass.expect_once(bypass, "POST", "/twirp/livekit.Ingress/ListIngress", fn conn ->
        ["Bearer " <> token] = Plug.Conn.get_req_header(conn, "authorization")

        refute token =~ @api_secret
        assert {:ok, claims} = Livekit.AccessToken.verify(token, @api_key, @api_secret)
        assert claims["video"]["ingressAdmin"] == true

        respond(conn, Livekit.ListIngressResponse, %Livekit.ListIngressResponse{})
      end)

      assert {:ok, _} = IngressServiceClient.list_ingress(client)
    end
  end

  describe "create_ingress/2" do
    test "posts to the Twirp path and returns the endpoint credentials", %{
      bypass: bypass,
      client: client
    } do
      Bypass.expect_once(bypass, "POST", "/twirp/livekit.Ingress/CreateIngress", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Livekit.CreateIngressRequest.decode(body)

        assert request.input_type == :RTMP_INPUT
        assert request.room_name == "my-room"
        assert request.participant_identity == "streamer"

        respond(conn, Livekit.IngressInfo, %Livekit.IngressInfo{
          ingress_id: "IN_abc",
          name: "my-stream",
          url: "rtmp://ingress.livekit.cloud/live",
          stream_key: "sk_test"
        })
      end)

      request = %Livekit.CreateIngressRequest{
        input_type: :RTMP_INPUT,
        name: "my-stream",
        room_name: "my-room",
        participant_identity: "streamer"
      }

      assert {:ok, info} = IngressServiceClient.create_ingress(client, request)
      assert info.ingress_id == "IN_abc"
      assert info.stream_key == "sk_test"
    end

    test "surfaces a Twirp error", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(400, ~s({"code":"invalid_argument","msg":"room_name is required"}))
      end)

      assert {:error, {400, body}} =
               IngressServiceClient.create_ingress(client, %Livekit.CreateIngressRequest{})

      assert body =~ "room_name is required"
    end
  end

  describe "update_ingress/2" do
    test "posts the ingress id and changed fields", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/twirp/livekit.Ingress/UpdateIngress", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Livekit.UpdateIngressRequest.decode(body)

        assert request.ingress_id == "IN_abc"
        assert request.name == "renamed"

        respond(conn, Livekit.IngressInfo, %Livekit.IngressInfo{
          ingress_id: "IN_abc",
          name: "renamed"
        })
      end)

      request = %Livekit.UpdateIngressRequest{ingress_id: "IN_abc", name: "renamed"}
      assert {:ok, info} = IngressServiceClient.update_ingress(client, request)
      assert info.name == "renamed"
    end
  end

  describe "list_ingress/2" do
    test "decodes the items", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/twirp/livekit.Ingress/ListIngress", fn conn ->
        respond(conn, Livekit.ListIngressResponse, %Livekit.ListIngressResponse{
          items: [
            %Livekit.IngressInfo{ingress_id: "IN_1", name: "one"},
            %Livekit.IngressInfo{ingress_id: "IN_2", name: "two"}
          ]
        })
      end)

      assert {:ok, %Livekit.ListIngressResponse{items: [one, two]}} =
               IngressServiceClient.list_ingress(client)

      assert one.ingress_id == "IN_1"
      assert two.ingress_id == "IN_2"
    end
  end

  describe "delete_ingress/2" do
    test "posts the ingress id", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/twirp/livekit.Ingress/DeleteIngress", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Livekit.DeleteIngressRequest.decode(body).ingress_id == "IN_abc"

        respond(conn, Livekit.IngressInfo, %Livekit.IngressInfo{ingress_id: "IN_abc"})
      end)

      request = %Livekit.DeleteIngressRequest{ingress_id: "IN_abc"}
      assert {:ok, info} = IngressServiceClient.delete_ingress(client, request)
      assert info.ingress_id == "IN_abc"
    end
  end

  defp respond(conn, module, message) do
    conn
    |> Plug.Conn.put_resp_content_type("application/protobuf")
    |> Plug.Conn.resp(200, module.encode(message))
  end
end

defmodule Livekit.ProtoFieldNumbersTest do
  @moduledoc """
  Pins the wire format against LiveKit's published schema.

  The `.proto` files here were once abridged transcriptions of LiveKit's,
  written by hand. Every message still had plausible-looking fields, so
  nothing looked wrong until the bytes came back from a real server and
  refused to decode: `EgressInfo.status` was numbered 4 where LiveKit numbers
  it 3, and field 4 on the wire is `room_composite`, a message. A struct
  expecting an enum got a length-delimited value and raised.

  A field *name* is a local convenience; the *number* is the contract. These
  assertions exist so that a hand-edit to a generated module, or a
  regeneration from the wrong source, fails here rather than against a
  customer's egress.

  Numbers below are from livekit/protocol (see proto/UPSTREAM_VERSION).
  """

  use ExUnit.Case, async: true

  defp fnums(module) do
    module.__message_props__().field_props
    |> Map.new(fn {fnum, props} -> {props.name_atom, fnum} end)
  end

  describe "EgressInfo — the message that exposed the drift" do
    test "carries LiveKit's field numbers, not a plausible re-numbering" do
      f = fnums(Livekit.EgressInfo)

      assert f.egress_id == 1
      assert f.room_id == 2
      # Was 4 in the hand-written proto. Field 4 is room_composite.
      assert f.status == 3
      # Was 3 in the hand-written proto.
      assert f.room_name == 13
      # Was 5 in the hand-written proto.
      assert f.error == 9
      assert f.room_composite == 4
      assert f.started_at == 10
      assert f.ended_at == 11
      assert f.stream_results == 15
      assert f.source_type == 26
    end

    test "reports each destination separately, so one bad stream key is distinguishable" do
      assert %Livekit.EgressInfo{}
             |> Map.fetch!(:stream_results) == []

      f = fnums(Livekit.StreamInfo)
      assert Map.has_key?(f, :url)
      assert Map.has_key?(f, :status)
      assert Map.has_key?(f, :error)
    end
  end

  describe "RTMP output" do
    test "StreamOutput carries protocol and urls" do
      f = fnums(Livekit.StreamOutput)
      assert f.protocol == 1
      assert f.urls == 2
    end

    test "RTMP is protocol 1" do
      assert Livekit.StreamProtocol.value(:RTMP) == 1
      assert Livekit.StreamProtocol.value(:SRT) == 2
    end

    test "stream_outputs is the repeated field on a room composite request" do
      assert fnums(Livekit.RoomCompositeEgressRequest).stream_outputs == 12
    end
  end

  describe "storage upload targets — every bucket field was wrong" do
    test "S3Upload.bucket is 5, not 1" do
      assert fnums(Livekit.S3Upload).bucket == 5
    end

    test "GCPUpload has credentials before bucket" do
      f = fnums(Livekit.GCPUpload)
      assert f.credentials == 1
      assert f.bucket == 2
    end

    test "AzureBlobUpload.container_name is 3, not 1" do
      assert fnums(Livekit.AzureBlobUpload).container_name == 3
    end

    test "AliOSSUpload.bucket is 5, not 1" do
      assert fnums(Livekit.AliOSSUpload).bucket == 5
    end
  end

  describe "RoomAgentDispatch — a message that never existed as written" do
    test "is agent_name/metadata, not name/identity/init_request" do
      f = fnums(Livekit.RoomAgentDispatch)

      assert f.agent_name == 1
      assert f.metadata == 2
      refute Map.has_key?(f, :identity)
      refute Map.has_key?(f, :init_request)
    end

    test "Livekit.InitRequest does not exist" do
      refute Code.ensure_loaded?(Livekit.InitRequest)
    end
  end

  describe "SendDataRequest — quietly wrong, and nothing used it" do
    test "destination_identities is 6 and nonce is 7" do
      f = fnums(Livekit.SendDataRequest)
      assert f.destination_identities == 6
      assert f.nonce == 7
    end
  end

  describe "round trip" do
    test "an EgressInfo survives encode/decode with its status intact" do
      info = %Livekit.EgressInfo{
        egress_id: "EG_test",
        room_name: "session_42",
        status: :EGRESS_ACTIVE,
        stream_results: [
          %Livekit.StreamInfo{url: "rtmp://host/live/key", status: :ACTIVE}
        ]
      }

      decoded = info |> Livekit.EgressInfo.encode() |> Livekit.EgressInfo.decode()

      assert decoded.egress_id == "EG_test"
      assert decoded.room_name == "session_42"
      assert decoded.status == :EGRESS_ACTIVE
      assert [%Livekit.StreamInfo{url: "rtmp://host/live/key"}] = decoded.stream_results
    end

    test "a room composite request with two RTMP destinations round trips" do
      request = %Livekit.RoomCompositeEgressRequest{
        room_name: "session_42",
        layout: "grid",
        stream_outputs: [
          %Livekit.StreamOutput{
            protocol: :RTMP,
            urls: [
              "rtmp://a.rtmp.youtube.com/live2/k1",
              "rtmps://live-api-s.facebook.com/rtmp/k2"
            ]
          }
        ],
        options: {:preset, :H264_720P_30}
      }

      decoded =
        request
        |> Livekit.RoomCompositeEgressRequest.encode()
        |> Livekit.RoomCompositeEgressRequest.decode()

      assert [%Livekit.StreamOutput{protocol: :RTMP, urls: [yt, fb]}] = decoded.stream_outputs
      assert yt =~ "youtube"
      assert fb =~ "facebook"
      assert decoded.options == {:preset, :H264_720P_30}
    end
  end
end

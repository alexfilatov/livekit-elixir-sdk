defmodule Livekit.Agents.Telephony.SIPTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.Telephony.SIP
  alias Livekit.Agents.Telephony.SIP.SIPParticipant

  describe "detect_sip_participant/1" do
    test "detects inbound SIP participant from livekit.sip.* attributes" do
      attrs = %{
        "livekit.sip.callID" => "call-abc-123",
        "livekit.sip.phoneNumber" => "+15551234567",
        "livekit.sip.callDirection" => "inbound",
        "livekit.sip.trunkID" => "trunk-42",
        "livekit.sip.dialedNumber" => "+18005551234"
      }

      assert {:ok, %SIPParticipant{} = sip} = SIP.detect_sip_participant(attrs)
      assert sip.call_id == "call-abc-123"
      assert sip.phone_number == "+15551234567"
      assert sip.direction == :inbound
      assert sip.trunk_id == "trunk-42"
      assert sip.dialed_number == "+18005551234"
      assert sip.metadata == attrs
    end

    test "detects outbound SIP participant" do
      attrs = %{
        "livekit.sip.callID" => "call-out-999",
        "livekit.sip.callDirection" => "outbound",
        "livekit.sip.phoneNumber" => "+15559876543"
      }

      assert {:ok, %SIPParticipant{} = sip} = SIP.detect_sip_participant(attrs)
      assert sip.direction == :outbound
      assert sip.call_id == "call-out-999"
    end

    test "falls back to sip.callID attribute key" do
      attrs = %{"sip.callID" => "fallback-id"}

      assert {:ok, %SIPParticipant{} = sip} = SIP.detect_sip_participant(attrs)
      assert sip.call_id == "fallback-id"
    end

    test "falls back to sip.call_id attribute key" do
      attrs = %{"sip.call_id" => "snake-case-id"}

      assert {:ok, %SIPParticipant{} = sip} = SIP.detect_sip_participant(attrs)
      assert sip.call_id == "snake-case-id"
    end

    test "returns not_a_sip_participant for non-SIP participant" do
      attrs = %{"kind" => "standard", "name" => "Alice"}

      assert {:error, :not_a_sip_participant} = SIP.detect_sip_participant(attrs)
    end

    test "returns not_a_sip_participant for empty map" do
      assert {:error, :not_a_sip_participant} = SIP.detect_sip_participant(%{})
    end

    test "handles participant with call_id but no phone number" do
      attrs = %{"livekit.sip.callID" => "anon-call"}

      assert {:ok, %SIPParticipant{} = sip} = SIP.detect_sip_participant(attrs)
      assert sip.call_id == "anon-call"
      assert sip.phone_number == nil
      assert sip.direction == nil
    end

    test "handles unknown direction string gracefully" do
      attrs = %{
        "livekit.sip.callID" => "id",
        "livekit.sip.callDirection" => "unknown_direction"
      }

      assert {:ok, %SIPParticipant{} = sip} = SIP.detect_sip_participant(attrs)
      assert sip.direction == nil
    end
  end

  describe "call_info/1" do
    test "returns map with all call metadata" do
      sip = %SIPParticipant{
        call_id: "call-123",
        phone_number: "+15551234567",
        dialed_number: "+18005559999",
        direction: :inbound,
        trunk_id: "trunk-99"
      }

      info = SIP.call_info(sip)

      assert info["call_id"] == "call-123"
      assert info["phone_number"] == "+15551234567"
      assert info["dialed_number"] == "+18005559999"
      assert info["direction"] == "inbound"
      assert info["trunk_id"] == "trunk-99"
    end

    test "returns outbound direction as string" do
      sip = %SIPParticipant{call_id: "x", direction: :outbound}
      assert SIP.call_info(sip)["direction"] == "outbound"
    end

    test "returns nil direction for unknown direction" do
      sip = %SIPParticipant{call_id: "x", direction: nil}
      assert SIP.call_info(sip)["direction"] == nil
    end

    test "returns nil for absent optional fields" do
      sip = %SIPParticipant{call_id: "x"}
      info = SIP.call_info(sip)
      assert info["phone_number"] == nil
      assert info["dialed_number"] == nil
      assert info["trunk_id"] == nil
    end
  end
end

defmodule Livekit.Agents.Telephony.WarmTransferTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.Telephony.SIP.SIPParticipant
  alias Livekit.Agents.Telephony.WarmTransfer

  # Helper: build a test SIP participant
  defp test_participant(overrides \\ %{}) do
    Map.merge(
      %SIPParticipant{
        call_id: "call-test-123",
        phone_number: "+15551234567",
        direction: :inbound
      },
      overrides
    )
  end

  describe "transfer/3 — cold transfer" do
    test "returns transfer instruction for E.164 destination" do
      sip = test_participant()

      assert {:ok, instruction} = WarmTransfer.transfer(:room, sip, "+15559990000")

      assert instruction["type"] == "transfer"
      assert instruction["call_id"] == "call-test-123"
      assert instruction["destination"] == "+15559990000"
      assert instruction["source_phone"] == "+15551234567"
      assert instruction["transfer_mode"] == "cold"
      assert is_binary(instruction["timestamp"])
    end

    test "timestamp is ISO 8601 UTC format" do
      sip = test_participant()
      assert {:ok, instruction} = WarmTransfer.transfer(:room, sip, "+15559990000")
      assert {:ok, _dt, 0} = DateTime.from_iso8601(instruction["timestamp"])
    end

    test "accepts SIP URI as destination" do
      sip = test_participant()
      assert {:ok, instruction} = WarmTransfer.transfer(:room, sip, "sip:agent@pbx.example.com")
      assert instruction["destination"] == "sip:agent@pbx.example.com"
    end

    test "accepts sips: URI as destination" do
      sip = test_participant()
      assert {:ok, _} = WarmTransfer.transfer(:room, sip, "sips:secure@pbx.example.com")
    end

    test "returns error for invalid destination" do
      sip = test_participant()
      assert {:error, :invalid_destination} = WarmTransfer.transfer(:room, sip, "not-a-number")
    end

    test "returns error for invalid destination: short number" do
      sip = test_participant()
      # Too short for E.164 (needs at least 7 digits after +)
      assert {:error, :invalid_destination} = WarmTransfer.transfer(:room, sip, "+123")
    end

    test "accepts participant with nil phone_number" do
      sip = test_participant(%{phone_number: nil})
      assert {:ok, instruction} = WarmTransfer.transfer(:room, sip, "+15559990000")
      assert instruction["source_phone"] == nil
    end
  end

  describe "warm_transfer/4 — warm transfer" do
    test "returns warm transfer instruction with context" do
      sip = test_participant()

      assert {:ok, instruction} =
               WarmTransfer.warm_transfer(:room, sip, "+15559990000",
                 context: "Caller wants billing help."
               )

      assert instruction["type"] == "warm_transfer"
      assert instruction["call_id"] == "call-test-123"
      assert instruction["destination"] == "+15559990000"
      assert instruction["transfer_mode"] == "warm"
      assert instruction["context"] == "Caller wants billing help."
      assert instruction["whisper_timeout_ms"] == 30_000
      assert is_binary(instruction["timestamp"])
    end

    test "uses default empty context when not provided" do
      sip = test_participant()
      assert {:ok, instruction} = WarmTransfer.warm_transfer(:room, sip, "+15559990000")
      assert instruction["context"] == ""
    end

    test "accepts custom whisper_timeout_ms" do
      sip = test_participant()

      assert {:ok, instruction} =
               WarmTransfer.warm_transfer(:room, sip, "+15559990000", whisper_timeout_ms: 15_000)

      assert instruction["whisper_timeout_ms"] == 15_000
    end

    test "returns error for invalid destination" do
      sip = test_participant()
      assert {:error, :invalid_destination} = WarmTransfer.warm_transfer(:room, sip, "bad")
    end

    test "includes source phone in instruction" do
      sip = test_participant(%{phone_number: "+15550001234"})
      assert {:ok, instruction} = WarmTransfer.warm_transfer(:room, sip, "+15559990000")
      assert instruction["source_phone"] == "+15550001234"
    end

    test "timestamp is ISO 8601 UTC format" do
      sip = test_participant()
      assert {:ok, instruction} = WarmTransfer.warm_transfer(:room, sip, "+15559990000")
      assert {:ok, _dt, 0} = DateTime.from_iso8601(instruction["timestamp"])
    end
  end
end

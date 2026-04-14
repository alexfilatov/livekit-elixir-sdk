defmodule Livekit.WebRTC.ParticipantTest do
  use ExUnit.Case, async: true

  alias Livekit.WebRTC.Participant

  describe "Participant.new/2" do
    test "creates a participant with identity only" do
      participant = Participant.new("alice")
      assert participant.identity == "alice"
      assert participant.metadata == nil
    end

    test "creates a participant with identity and metadata" do
      participant = Participant.new("alice", ~s({"role":"agent"}))
      assert participant.identity == "alice"
      assert participant.metadata == ~s({"role":"agent"})
    end
  end

  describe "Participant.identity/1" do
    test "returns the participant identity" do
      participant = Participant.new("bob")
      assert Participant.identity(participant) == "bob"
    end
  end

  describe "Participant.metadata/1" do
    test "returns nil when no metadata set" do
      participant = Participant.new("carol")
      assert Participant.metadata(participant) == nil
    end

    test "returns metadata string when set" do
      participant = Participant.new("carol", "some-metadata")
      assert Participant.metadata(participant) == "some-metadata"
    end
  end
end

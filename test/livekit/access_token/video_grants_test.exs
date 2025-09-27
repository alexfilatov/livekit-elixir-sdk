defmodule Livekit.AccessToken.VideoGrantsTest do
  use ExUnit.Case
  alias Livekit.AccessToken.VideoGrants

  describe "join_room/3" do
    test "creates a room join grant" do
      grant = VideoGrants.join_room("test_room")
      assert grant.room == "test_room"
      assert grant.room_join == true
      refute grant.room_admin
      refute grant.room_create
    end
  end

  describe "room_admin/0" do
    test "creates a room admin grant" do
      grant = VideoGrants.room_admin()
      assert grant.room_admin == true
      refute grant.room_join
      refute grant.room_create
    end
  end

  describe "room_create/0" do
    test "creates a room create grant" do
      grant = VideoGrants.room_create()
      assert grant.room_create == true
      refute grant.room_join
      refute grant.room_admin
    end
  end

  describe "ingress_admin/0" do
    test "creates an ingress admin grant" do
      grant = VideoGrants.ingress_admin()
      assert grant.ingress_admin == true
      refute grant.room_join
      refute grant.room_admin
      refute grant.room_create
    end
  end

  describe "update_grants/2" do
    test "updates the grants with the given options" do
      base_grants = %VideoGrants{}

      assert base_grants.room_join == nil
      updated_grant = VideoGrants.update_grants(base_grants, room_join: true)
      assert updated_grant.room_join == true

      assert updated_grant.room == ""
      assert updated_grant.room_admin == nil
      assert updated_grant.room_create == nil
      assert updated_grant.hidden == nil
      assert updated_grant.agent == nil

      room_name = "test_room"

      updated_grant =
        VideoGrants.update_grants(
          updated_grant,
          room: room_name,
          room_admin: true,
          room_create: true,
          hidden: true,
          agent: true
        )

      assert updated_grant.room == room_name
      assert updated_grant.room_admin == true
      assert updated_grant.room_create == true
      assert updated_grant.hidden == true
      assert updated_grant.agent == true
    end
  end
end

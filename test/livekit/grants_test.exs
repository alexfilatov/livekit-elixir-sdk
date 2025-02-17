defmodule Livekit.GrantsTest do
  use ExUnit.Case
  alias Livekit.Grants

  describe "join_room/3" do
    test "creates a room join grant" do
      grant = Grants.join_room("test_room")
      assert grant.room == "test_room"
      assert grant.room_join == true
      refute grant.room_admin
      refute grant.room_create
    end
  end

  describe "room_admin/0" do
    test "creates a room admin grant" do
      grant = Grants.room_admin()
      assert grant.room_admin == true
      refute grant.room_join
      refute grant.room_create
    end
  end

  describe "room_create/0" do
    test "creates a room create grant" do
      grant = Grants.room_create()
      assert grant.room_create == true
      refute grant.room_join
      refute grant.room_admin
    end
  end

  describe "ingress_admin/0" do
    test "creates an ingress admin grant" do
      grant = Grants.ingress_admin()
      assert grant.ingress_admin == true
      refute grant.room_join
      refute grant.room_admin
      refute grant.room_create
    end
  end
end

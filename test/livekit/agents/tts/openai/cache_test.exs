defmodule Livekit.Agents.TTS.OpenAI.CacheTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.TTS.OpenAI.Cache

  describe "start_link/1" do
    test "starts with default options" do
      assert {:ok, pid} = Cache.start_link()
      assert is_pid(pid)
    end

    test "starts with custom ttl and max_entries" do
      assert {:ok, pid} = Cache.start_link(ttl_seconds: 60, max_entries: 10)
      assert is_pid(pid)
    end
  end

  describe "get/2" do
    test "returns :miss for unknown key" do
      {:ok, pid} = Cache.start_link()
      assert :miss = Cache.get(pid, "nonexistent")
    end

    test "returns {:ok, value} for stored key" do
      {:ok, pid} = Cache.start_link()
      Cache.put(pid, "k", "audio_bytes")
      assert {:ok, "audio_bytes"} = Cache.get(pid, "k")
    end

    test "returns :miss after TTL expires" do
      {:ok, pid} = Cache.start_link(ttl_seconds: 0)
      Cache.put(pid, "k", "v")
      Process.sleep(5)
      assert :miss = Cache.get(pid, "k")
    end

    test "returns {:ok, value} before TTL expires" do
      {:ok, pid} = Cache.start_link(ttl_seconds: 3600)
      Cache.put(pid, "k", "v")
      assert {:ok, "v"} = Cache.get(pid, "k")
    end
  end

  describe "put/3" do
    test "evicts oldest entry when max_entries reached" do
      {:ok, pid} = Cache.start_link(max_entries: 2)
      Cache.put(pid, "k1", "v1")
      Cache.put(pid, "k2", "v2")
      # third put triggers eviction of k1 (oldest)
      Cache.put(pid, "k3", "v3")
      assert :miss = Cache.get(pid, "k1")
      assert {:ok, "v2"} = Cache.get(pid, "k2")
      assert {:ok, "v3"} = Cache.get(pid, "k3")
    end

    test "updating existing key does not grow insertion_order unboundedly" do
      {:ok, pid} = Cache.start_link(max_entries: 2)
      Cache.put(pid, "k1", "v1")
      Cache.put(pid, "k1", "v1_updated")
      Cache.put(pid, "k2", "v2")
      # k1 updated in-place; neither should be evicted with 2 slots
      assert {:ok, "v1_updated"} = Cache.get(pid, "k1")
      assert {:ok, "v2"} = Cache.get(pid, "k2")
    end

    test "updating existing key returns new value" do
      {:ok, pid} = Cache.start_link()
      Cache.put(pid, "key", "original")
      Cache.put(pid, "key", "updated")
      assert {:ok, "updated"} = Cache.get(pid, "key")
    end
  end

  describe "clear/1" do
    test "removes all entries" do
      {:ok, pid} = Cache.start_link()
      Cache.put(pid, "k1", "v1")
      Cache.put(pid, "k2", "v2")
      Cache.clear(pid)
      assert :miss = Cache.get(pid, "k1")
      assert :miss = Cache.get(pid, "k2")
    end

    test "clears empty cache without error" do
      {:ok, pid} = Cache.start_link()
      assert :ok = Cache.clear(pid)
    end

    test "allows new entries after clear" do
      {:ok, pid} = Cache.start_link()
      Cache.put(pid, "k1", "v1")
      Cache.clear(pid)
      Cache.put(pid, "k2", "v2")
      assert :miss = Cache.get(pid, "k1")
      assert {:ok, "v2"} = Cache.get(pid, "k2")
    end
  end
end

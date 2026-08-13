defmodule Livekit.WebRTC.RoomTest do
  use ExUnit.Case, async: true

  alias Livekit.WebRTC.Room

  # Mock NIF module — no real LiveKit server or compiled NIF required (D-19)
  defmodule MockNative do
    @moduledoc false

    def room_connect(_url, _token, _pid), do: {:ok, make_ref()}
    def room_disconnect(_room_ref), do: :ok
    def audio_subscribe(_room_ref, _track_sid, _subscriber_pid), do: {:ok, make_ref()}
    def audio_publish_frame(_room_ref, _binary, _sr, _ch), do: :ok
  end

  defmodule MockNativeConnectError do
    @moduledoc false

    def room_connect(_url, _token, _pid), do: {:error, "connection refused"}
    def room_disconnect(_room_ref), do: :ok
  end

  defp mock_config(opts \\ []) do
    nif = Keyword.get(opts, :nif_module, MockNative)

    %Room.Config{
      url: "wss://test.livekit.io",
      token: "test-token",
      nif_module: nif
    }
  end

  describe "Room.connect/1" do
    test "returns {:ok, pid} when NIF connect succeeds" do
      assert {:ok, pid} = Room.connect(mock_config())
      assert is_pid(pid)
      Room.disconnect(pid)
    end

    test "returns {:error, reason} when NIF connect fails" do
      assert {:error, _reason} = Room.connect(mock_config(nif_module: MockNativeConnectError))
    end
  end

  describe "subscribe_events/2" do
    test "registered subscriber receives forwarded room events" do
      {:ok, room_pid} = Room.connect(mock_config())
      :ok = Room.subscribe_events(room_pid, self())

      # Simulate event from Rust event loop
      send(room_pid, {:participant_connected, "alice"})

      assert_receive {:participant_connected, "alice"}, 1_000
      Room.disconnect(room_pid)
    end

    test "handles all D-12 event types without crashing" do
      {:ok, room_pid} = Room.connect(mock_config())
      :ok = Room.subscribe_events(room_pid, self())

      events = [
        {:participant_connected, "alice"},
        {:participant_disconnected, "alice"},
        {:track_subscribed, "TR_abc123", "alice", :audio},
        {:track_unsubscribed, "TR_abc123", "alice"},
        {:track_published, "TR_abc123", "alice"},
        {:track_unpublished, "TR_abc123", "alice"},
        {:data_received, "hello", "chat", "alice"},
        {:connection_quality_changed, "alice", "Excellent"}
      ]

      Enum.each(events, fn event -> send(room_pid, event) end)

      Enum.each(events, fn event ->
        assert_receive ^event, 500
      end)

      Room.disconnect(room_pid)
    end
  end

  describe "disconnected event" do
    test "GenServer stops normally when :disconnected event received" do
      {:ok, room_pid} = Room.connect(mock_config())
      ref = Process.monitor(room_pid)

      send(room_pid, {:disconnected, "server closed"})

      assert_receive {:DOWN, ^ref, :process, ^room_pid, :normal}, 1_000
    end
  end

  describe "get_metrics/1" do
    test "tracks events_received count" do
      {:ok, room_pid} = Room.connect(mock_config())

      send(room_pid, {:participant_connected, "alice"})
      send(room_pid, {:participant_connected, "bob"})
      # Give GenServer time to process
      :timer.sleep(50)

      metrics = Room.get_metrics(room_pid)
      assert metrics.events_received == 2

      Room.disconnect(room_pid)
    end

    test "tracks_subscribed increments on track_subscribed events" do
      {:ok, room_pid} = Room.connect(mock_config())

      send(room_pid, {:track_subscribed, "TR_1", "alice", :audio})
      send(room_pid, {:track_subscribed, "TR_2", "bob", :audio})
      :timer.sleep(50)

      metrics = Room.get_metrics(room_pid)
      assert metrics.tracks_subscribed == 2

      Room.disconnect(room_pid)
    end
  end

  describe "room_ref/1" do
    test "returns the opaque NIF room reference" do
      {:ok, room_pid} = Room.connect(mock_config())
      ref = Room.room_ref(room_pid)
      assert is_reference(ref)
      Room.disconnect(room_pid)
    end
  end

  describe "nif_module/1" do
    test "returns the configured NIF module" do
      {:ok, room_pid} = Room.connect(mock_config())
      assert Room.nif_module(room_pid) == MockNative
      Room.disconnect(room_pid)
    end
  end
end

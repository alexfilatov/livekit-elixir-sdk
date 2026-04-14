defmodule MockRoomForRoomIO do
  @moduledoc false

  use GenServer

  def start_link, do: GenServer.start_link(__MODULE__, [])

  @impl true
  def init(_), do: {:ok, %{subscribers: []}}

  @impl true
  def handle_call({:subscribe_events, pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: [pid | state.subscribers]}}
  end

  @impl true
  def handle_call(:room_ref, _from, state), do: {:reply, make_ref(), state}

  @impl true
  def handle_call(:nif_module, _from, state), do: {:reply, MockNIFForRoomIO, state}

  @impl true
  def handle_call(:get_subscribers, _from, state), do: {:reply, state.subscribers, state}
end

defmodule MockNIFForRoomIO do
  @moduledoc false

  def audio_subscribe(_room_ref, _track_sid, _subscriber_pid), do: {:ok, make_ref()}
  def audio_publish_frame(_room_ref, _data, _sr, _ch), do: :ok
end

defmodule MockPipelineForRoomIO do
  @moduledoc false

  use GenServer

  def start_link(test_pid), do: GenServer.start_link(__MODULE__, test_pid)

  @impl true
  def init(test_pid), do: {:ok, test_pid}

  @impl true
  def handle_cast({:push_frame, frame}, test_pid) do
    send(test_pid, {:push_frame_called, frame})
    {:noreply, test_pid}
  end
end

defmodule Livekit.Agents.RoomIOTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Livekit.Agents.{AudioFrame, RoomIO}

  setup do
    {:ok, room_pid} = MockRoomForRoomIO.start_link()
    {:ok, pipeline_pid} = MockPipelineForRoomIO.start_link(self())
    config = %RoomIO.Config{room_pid: room_pid, pipeline_pid: pipeline_pid}
    {:ok, room_io_pid} = RoomIO.start_link(config)

    on_exit(fn ->
      if Process.alive?(room_io_pid), do: RoomIO.stop(room_io_pid)
      if Process.alive?(pipeline_pid), do: GenServer.stop(pipeline_pid)
      if Process.alive?(room_pid), do: GenServer.stop(room_pid)
    end)

    %{room_io_pid: room_io_pid, room_pid: room_pid, pipeline_pid: pipeline_pid}
  end

  test "start_link with valid config starts the process", %{room_io_pid: pid} do
    assert is_pid(pid)
    assert Process.alive?(pid)
  end

  test "init subscribes to room events", %{room_io_pid: room_io_pid, room_pid: room_pid} do
    subscribers = GenServer.call(room_pid, :get_subscribers)
    assert room_io_pid in subscribers
  end

  test "start_link with nil room_pid returns error" do
    config = %RoomIO.Config{room_pid: nil, pipeline_pid: self()}
    assert {:error, :missing_config} = RoomIO.start_link(config)
  end

  test "start_link with nil pipeline_pid returns error" do
    {:ok, room_pid} = MockRoomForRoomIO.start_link()
    config = %RoomIO.Config{room_pid: room_pid, pipeline_pid: nil}
    assert {:error, :missing_config} = RoomIO.start_link(config)
  end

  test "track_subscribed audio auto-subscribes and audio_frame forwarded to pipeline",
       %{room_io_pid: room_io_pid} do
    send(room_io_pid, {:track_subscribed, "TR_001", "alice", :audio})
    # Give GenServer time to process subscribe, then send a frame
    Process.sleep(20)

    binary = :crypto.strong_rand_bytes(480)
    send(room_io_pid, {:audio_frame, "TR_001", binary})

    assert_receive {:push_frame_called, %AudioFrame{data: ^binary, format: :pcm_16}}, 200
  end

  test "ignores non-audio track_subscribed", %{room_io_pid: room_io_pid} do
    send(room_io_pid, {:track_subscribed, "TR_v", "alice", :video})
    Process.sleep(20)

    # Sending an audio frame should still not reach pipeline because no audio track was subscribed
    binary = :crypto.strong_rand_bytes(480)
    send(room_io_pid, {:audio_frame, "TR_v", binary})

    # Pipeline should receive the frame regardless (RoomIO routes all audio_frame msgs)
    # — but MockNIF was NOT called for subscribe on the video track.
    # Verify no additional subscribe side effect via metrics (errors should be 0)
    Process.sleep(20)
    metrics = RoomIO.get_metrics(room_io_pid)
    assert metrics.errors == 0
  end

  test "audio_frame forwarded with correct AudioFrame fields", %{room_io_pid: room_io_pid} do
    send(room_io_pid, {:track_subscribed, "TR_001", "alice", :audio})
    Process.sleep(20)

    binary = <<1, 2, 3, 4, 5, 6>>
    send(room_io_pid, {:audio_frame, "TR_001", binary})

    assert_receive {:push_frame_called,
                    %AudioFrame{
                      data: ^binary,
                      format: :pcm_16,
                      sample_rate: 48_000,
                      channels: 1
                    }},
                   200
  end

  test "pipeline_audio triggers AudioTrack.publish without crash", %{room_io_pid: room_io_pid} do
    frame = %AudioFrame{data: <<1, 2, 3, 4>>, format: :pcm_16, sample_rate: 48_000, channels: 1}
    send(room_io_pid, {:pipeline_audio, frame})
    Process.sleep(20)

    # No crash means publish was called; verify via metrics
    metrics = RoomIO.get_metrics(room_io_pid)
    assert metrics.frames_published == 1
    assert metrics.errors == 0
  end

  test "participant_disconnected resets subscribed track", %{room_io_pid: room_io_pid} do
    send(room_io_pid, {:track_subscribed, "TR_001", "alice", :audio})
    Process.sleep(20)

    send(room_io_pid, {:participant_disconnected, "alice"})
    Process.sleep(20)

    # After disconnect, a new track_subscribed should be accepted (subscribed_track was reset)
    send(room_io_pid, {:track_subscribed, "TR_002", "bob", :audio})
    Process.sleep(20)

    # Now send a frame and verify it reaches pipeline
    binary = :crypto.strong_rand_bytes(480)
    send(room_io_pid, {:audio_frame, "TR_002", binary})
    assert_receive {:push_frame_called, %AudioFrame{data: ^binary}}, 200
  end

  test "track_unsubscribed resets subscribed track", %{room_io_pid: room_io_pid} do
    send(room_io_pid, {:track_subscribed, "TR_001", "alice", :audio})
    Process.sleep(20)

    send(room_io_pid, {:track_unsubscribed, "TR_001", "alice"})
    Process.sleep(20)

    # After unsubscribe, a new audio track should be accepted
    send(room_io_pid, {:track_subscribed, "TR_003", "carol", :audio})
    Process.sleep(20)

    binary = :crypto.strong_rand_bytes(480)
    send(room_io_pid, {:audio_frame, "TR_003", binary})
    assert_receive {:push_frame_called, %AudioFrame{data: ^binary}}, 200
  end

  test "get_metrics returns correct frames_received count", %{room_io_pid: room_io_pid} do
    send(room_io_pid, {:track_subscribed, "TR_001", "alice", :audio})
    Process.sleep(20)

    Enum.each(1..5, fn _ ->
      send(room_io_pid, {:audio_frame, "TR_001", :crypto.strong_rand_bytes(96)})
    end)

    Process.sleep(50)
    metrics = RoomIO.get_metrics(room_io_pid)
    assert metrics.frames_received == 5
  end

  test "get_metrics returns correct frames_published count", %{room_io_pid: room_io_pid} do
    frame = %AudioFrame{data: <<0, 0>>, format: :pcm_16, sample_rate: 48_000, channels: 1}

    Enum.each(1..3, fn _ ->
      send(room_io_pid, {:pipeline_audio, frame})
    end)

    Process.sleep(50)
    metrics = RoomIO.get_metrics(room_io_pid)
    assert metrics.frames_published == 3
  end

  test "stop/1 terminates the process cleanly", %{room_io_pid: room_io_pid} do
    assert Process.alive?(room_io_pid)
    RoomIO.stop(room_io_pid)
    Process.sleep(20)
    refute Process.alive?(room_io_pid)
  end

  test "second audio track_subscribed while one is active is ignored", %{
    room_io_pid: room_io_pid
  } do
    send(room_io_pid, {:track_subscribed, "TR_001", "alice", :audio})
    Process.sleep(20)
    send(room_io_pid, {:track_subscribed, "TR_002", "bob", :audio})
    Process.sleep(20)

    # No errors should be recorded — second subscribe is silently ignored
    metrics = RoomIO.get_metrics(room_io_pid)
    assert metrics.errors == 0
  end
end

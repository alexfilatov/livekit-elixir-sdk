defmodule Livekit.WebRTC.AudioTrackTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.AudioFrame
  alias Livekit.WebRTC.{AudioTrack, Room}

  # Mock NIF that captures calls for assertion (D-19)
  defmodule MockNative do
    @moduledoc false

    def room_connect(_url, _token, _pid), do: {:ok, make_ref()}
    def room_disconnect(_room_ref), do: :ok

    def audio_subscribe(_room_ref, track_sid, subscriber_pid) do
      send(subscriber_pid, {:mock_subscribe_called, track_sid})
      {:ok, make_ref()}
    end

    def audio_publish_frame(_room_ref, binary, sr, ch) do
      send(self(), {:mock_publish_called, byte_size(binary), sr, ch})
      :ok
    end
  end

  defmodule MockNativePublishError do
    @moduledoc false

    def room_connect(_url, _token, _pid), do: {:ok, make_ref()}
    def room_disconnect(_room_ref), do: :ok
    def audio_publish_frame(_room_ref, _binary, _sr, _ch), do: {:error, "publish failed"}
  end

  defp mock_config(nif_module \\ MockNative) do
    %Room.Config{
      url: "wss://test.livekit.io",
      token: "test-token",
      nif_module: nif_module
    }
  end

  describe "AudioTrack.publish/2" do
    test "calls NIF audio_publish_frame with correct binary and metadata" do
      {:ok, room_pid} = Room.connect(mock_config())

      frame = AudioFrame.new(<<0, 0, 0, 0>>, sample_rate: 48_000, channels: 1, format: :pcm_16)

      assert :ok = AudioTrack.publish(room_pid, frame)

      assert_receive {:mock_publish_called, 4, 48_000, 1}, 500

      Room.disconnect(room_pid)
    end

    test "returns error for unsupported audio format" do
      {:ok, room_pid} = Room.connect(mock_config())

      # float32 is not supported through the NIF (only :pcm_16)
      frame = %AudioFrame{
        data: <<0, 0, 0, 0>>,
        format: :float32,
        sample_rate: 48_000,
        channels: 1,
        samples_per_channel: 1
      }

      assert {:error, {:unsupported_format, :float32}} = AudioTrack.publish(room_pid, frame)

      Room.disconnect(room_pid)
    end

    test "forwards NIF error from audio_publish_frame" do
      {:ok, room_pid} = Room.connect(mock_config(MockNativePublishError))

      frame = AudioFrame.new(<<0, 0, 0, 0>>, sample_rate: 48_000, channels: 1, format: :pcm_16)

      assert {:error, "publish failed"} = AudioTrack.publish(room_pid, frame)

      Room.disconnect(room_pid)
    end
  end

  describe "AudioTrack.subscribe/3" do
    test "calls NIF audio_subscribe and returns track resource ref" do
      {:ok, room_pid} = Room.connect(mock_config())

      assert {:ok, track_ref} = AudioTrack.subscribe(room_pid, "TR_abc123", self())
      assert is_reference(track_ref)

      # MockNative sends a confirmation message so we can assert the call was made
      assert_receive {:mock_subscribe_called, "TR_abc123"}, 500

      Room.disconnect(room_pid)
    end
  end

  describe "AudioTrack.unsubscribe/1" do
    test "returns :ok for any reference (resource GC handles cleanup)" do
      assert :ok = AudioTrack.unsubscribe(make_ref())
    end

    test "returns :ok for nil (no-op)" do
      assert :ok = AudioTrack.unsubscribe(nil)
    end
  end
end

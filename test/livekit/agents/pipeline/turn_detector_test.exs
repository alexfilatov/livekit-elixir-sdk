defmodule Livekit.Agents.Pipeline.TurnDetectorTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.AudioFrame
  alias Livekit.Agents.Pipeline.TurnDetector

  # Helper: build a minimal PCM16 AudioFrame with the given timestamp
  defp make_frame(timestamp_us) do
    data = <<1000::little-signed-16>>

    AudioFrame.new(data,
      sample_rate: 16_000,
      channels: 1,
      format: :pcm_16,
      timestamp_us: timestamp_us
    )
  end

  # A frame whose RMS is clearly below 0.01 (near-silence)
  defp silent_frame do
    data = <<0::little-signed-16>>
    AudioFrame.new(data, sample_rate: 16_000, channels: 1, format: :pcm_16)
  end

  describe "start_link/1" do
    test "starts successfully with a subscriber pid" do
      assert {:ok, pid} = TurnDetector.start_link(subscriber: self())
      assert is_pid(pid)
      GenServer.stop(pid)
    end

    test "starts with custom silence_ms" do
      assert {:ok, pid} = TurnDetector.start_link(subscriber: self(), silence_ms: 200)
      assert is_pid(pid)
      GenServer.stop(pid)
    end

    test "fails when subscriber is not a pid" do
      assert {:error, _} = TurnDetector.start_link(subscriber: :not_a_pid)
    end
  end

  describe "push_frame/2 — speech onset" do
    test "sends {:turn_start, timestamp_us} to subscriber on first speech after silence" do
      {:ok, pid} = TurnDetector.start_link(subscriber: self(), silence_ms: 100)

      frame = make_frame(42_000)
      TurnDetector.push_frame(pid, {:speech, frame})

      assert_receive {:turn_start, 42_000}, 200
      GenServer.stop(pid)
    end

    test "does NOT send :turn_start again when already speaking" do
      {:ok, pid} = TurnDetector.start_link(subscriber: self(), silence_ms: 100)

      TurnDetector.push_frame(pid, {:speech, make_frame(1_000)})
      assert_receive {:turn_start, 1_000}, 200

      TurnDetector.push_frame(pid, {:speech, make_frame(2_000)})
      refute_receive {:turn_start, _}, 50

      GenServer.stop(pid)
    end
  end

  describe "push_frame/2 — silence timeout" do
    test "sends {:turn_end, frames} after silence_ms elapses" do
      {:ok, pid} = TurnDetector.start_link(subscriber: self(), silence_ms: 50)

      frame = make_frame(1_000)
      TurnDetector.push_frame(pid, {:speech, frame})
      assert_receive {:turn_start, 1_000}, 200

      TurnDetector.push_frame(pid, {:silence, silent_frame()})

      assert_receive {:turn_end, frames}, 300
      assert length(frames) == 1
      assert hd(frames).timestamp_us == 1_000

      GenServer.stop(pid)
    end

    test "accumulates multiple speech frames in :turn_end" do
      {:ok, pid} = TurnDetector.start_link(subscriber: self(), silence_ms: 50)

      TurnDetector.push_frame(pid, {:speech, make_frame(1_000)})
      assert_receive {:turn_start, _}, 200
      TurnDetector.push_frame(pid, {:speech, make_frame(2_000)})
      TurnDetector.push_frame(pid, {:speech, make_frame(3_000)})

      TurnDetector.push_frame(pid, {:silence, silent_frame()})

      assert_receive {:turn_end, frames}, 300
      assert length(frames) == 3

      GenServer.stop(pid)
    end
  end

  describe "push_frame/2 — timer reset on speech during silence window" do
    test "cancels pending silence timer when speech arrives" do
      {:ok, pid} = TurnDetector.start_link(subscriber: self(), silence_ms: 100)

      TurnDetector.push_frame(pid, {:speech, make_frame(1_000)})
      assert_receive {:turn_start, _}, 200

      # Start the silence window
      TurnDetector.push_frame(pid, {:silence, silent_frame()})

      # Speech arrives before the 100 ms timer fires
      Process.sleep(30)
      TurnDetector.push_frame(pid, {:speech, make_frame(2_000)})

      # No :turn_end should arrive in the original window
      refute_receive {:turn_end, _}, 150

      GenServer.stop(pid)
    end
  end

  describe "reset/1" do
    test "clears accumulated frames and resets state" do
      {:ok, pid} = TurnDetector.start_link(subscriber: self(), silence_ms: 200)

      TurnDetector.push_frame(pid, {:speech, make_frame(1_000)})
      assert_receive {:turn_start, _}, 200

      TurnDetector.reset(pid)

      # After reset, silence should not fire :turn_end from previous utterance
      TurnDetector.push_frame(pid, {:silence, silent_frame()})
      refute_receive {:turn_end, _}, 50

      GenServer.stop(pid)
    end

    test "cancels pending silence timer" do
      {:ok, pid} = TurnDetector.start_link(subscriber: self(), silence_ms: 50)

      TurnDetector.push_frame(pid, {:speech, make_frame(1_000)})
      assert_receive {:turn_start, _}, 200

      TurnDetector.push_frame(pid, {:silence, silent_frame()})
      TurnDetector.reset(pid)

      refute_receive {:turn_end, _}, 200

      GenServer.stop(pid)
    end
  end
end

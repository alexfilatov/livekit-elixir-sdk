defmodule Livekit.Agents.STT.AudioBufferTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.STT.AudioBuffer

  describe "new/1" do
    test "defaults min_duration_ms to 100" do
      buf = AudioBuffer.new()
      assert buf.min_duration_ms == 100
    end

    test "accepts custom min_duration_ms" do
      buf = AudioBuffer.new(min_duration_ms: 500)
      assert buf.min_duration_ms == 500
    end

    test "starts with empty data and zero duration" do
      buf = AudioBuffer.new()
      assert buf.data == <<>>
      assert buf.duration_ms == 0.0
    end
  end

  describe "push/3" do
    test "accumulates data binary" do
      buf = AudioBuffer.new()
      audio = <<1, 2, 3, 4>>
      buf2 = AudioBuffer.push(buf, audio, 48_000)
      assert buf2.data == audio
    end

    test "concatenates multiple pushes" do
      buf = AudioBuffer.new()
      buf2 = AudioBuffer.push(buf, <<1, 2>>, 48_000)
      buf3 = AudioBuffer.push(buf2, <<3, 4>>, 48_000)
      assert buf3.data == <<1, 2, 3, 4>>
    end

    test "increases duration_ms correctly for 16-bit mono PCM at 48kHz" do
      buf = AudioBuffer.new()
      # 9600 bytes = 4800 samples at 48kHz = 100ms
      audio = :binary.copy(<<0, 0>>, 4800)
      buf2 = AudioBuffer.push(buf, audio, 48_000)
      assert_in_delta buf2.duration_ms, 100.0, 0.1
    end

    test "accumulates duration_ms across multiple pushes" do
      buf = AudioBuffer.new()
      # 50ms at 48kHz = 2400 samples = 4800 bytes
      audio_50ms = :binary.copy(<<0, 0>>, 2400)
      buf2 = AudioBuffer.push(buf, audio_50ms, 48_000)
      buf3 = AudioBuffer.push(buf2, audio_50ms, 48_000)
      assert_in_delta buf3.duration_ms, 100.0, 0.1
    end
  end

  describe "flush_if_ready/1" do
    test "returns :buffering when under threshold" do
      buf = AudioBuffer.new(min_duration_ms: 200)
      # 50ms at 48kHz
      audio = :binary.copy(<<0, 0>>, 2400)
      buf2 = AudioBuffer.push(buf, audio, 48_000)
      assert {:buffering, ^buf2} = AudioBuffer.flush_if_ready(buf2)
    end

    test "returns :ready when threshold exactly met" do
      buf = AudioBuffer.new(min_duration_ms: 100)
      # 100ms at 48kHz = 4800 samples = 9600 bytes
      audio = :binary.copy(<<0, 0>>, 4800)
      buf2 = AudioBuffer.push(buf, audio, 48_000)
      assert {:ready, ^audio, reset_buf} = AudioBuffer.flush_if_ready(buf2)
      assert reset_buf.data == <<>>
      assert reset_buf.duration_ms == 0.0
    end

    test "returns :ready when threshold exceeded" do
      buf = AudioBuffer.new(min_duration_ms: 50)
      # 100ms at 48kHz
      audio = :binary.copy(<<0, 0>>, 4800)
      buf2 = AudioBuffer.push(buf, audio, 48_000)
      assert {:ready, ^audio, _reset_buf} = AudioBuffer.flush_if_ready(buf2)
    end

    test "reset buffer preserves min_duration_ms setting" do
      buf = AudioBuffer.new(min_duration_ms: 250)
      # push 3 x 100ms = 300ms, exceeds 250ms threshold
      audio = :binary.copy(<<0, 0>>, 4800)
      buf2 = AudioBuffer.push(buf, audio, 48_000)
      buf3 = AudioBuffer.push(buf2, audio, 48_000)
      buf4 = AudioBuffer.push(buf3, audio, 48_000)
      {:ready, _, reset_buf} = AudioBuffer.flush_if_ready(buf4)
      assert reset_buf.min_duration_ms == 250
    end

    test "returns :buffering for zero-duration buffer with min > 0" do
      buf = AudioBuffer.new(min_duration_ms: 100)
      assert {:buffering, ^buf} = AudioBuffer.flush_if_ready(buf)
    end
  end

  describe "flush/1" do
    test "always returns accumulated data regardless of duration threshold" do
      buf = AudioBuffer.new(min_duration_ms: 1000)
      audio = <<1, 2, 3, 4>>
      buf2 = AudioBuffer.push(buf, audio, 48_000)
      assert {^audio, reset_buf} = AudioBuffer.flush(buf2)
      assert reset_buf.data == <<>>
      assert reset_buf.duration_ms == 0.0
    end

    test "flush on empty buffer returns empty binary" do
      buf = AudioBuffer.new()
      assert {<<>>, _reset} = AudioBuffer.flush(buf)
    end

    test "reset buffer preserves min_duration_ms after flush" do
      buf = AudioBuffer.new(min_duration_ms: 300)
      audio = <<1, 2>>
      buf2 = AudioBuffer.push(buf, audio, 48_000)
      {_data, reset} = AudioBuffer.flush(buf2)
      assert reset.min_duration_ms == 300
    end
  end
end

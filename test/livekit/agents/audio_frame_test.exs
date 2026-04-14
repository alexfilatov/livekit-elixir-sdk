defmodule Livekit.Agents.AudioFrameTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.AudioFrame

  describe "AudioFrame creation" do
    test "creates frame with default parameters" do
      audio_data = <<1, 2, 3, 4>>
      frame = AudioFrame.new(audio_data)

      assert frame.data == audio_data
      assert frame.sample_rate == 48_000
      assert frame.channels == 1
      assert frame.format == :pcm_16
      assert frame.layout == :mono
    end

    test "creates frame with custom parameters" do
      audio_data = <<1, 2, 3, 4, 5, 6, 7, 8>>

      frame = AudioFrame.new(audio_data,
        sample_rate: 16_000,
        channels: 2,
        format: :pcm_24
      )

      assert frame.sample_rate == 16_000
      assert frame.channels == 2
      assert frame.format == :pcm_24
    end

    test "calculates duration correctly" do
      # 4800 bytes = 2400 samples at 16-bit = 50ms at 48kHz
      audio_data = :crypto.strong_rand_bytes(4800)
      frame = AudioFrame.new(audio_data, sample_rate: 48_000)

      assert frame.duration_us == 50_000  # 50ms in microseconds
      assert AudioFrame.duration_ms(frame) == 50.0
    end
  end

  describe "AudioFrame operations" do
    test "resamples audio" do
      audio_data = :crypto.strong_rand_bytes(4800)
      frame = AudioFrame.new(audio_data, sample_rate: 48_000)

      resampled = AudioFrame.resample(frame, 16_000)
      assert resampled.sample_rate == 16_000
      assert byte_size(resampled.data) != byte_size(frame.data)
    end

    test "converts audio format" do
      audio_data = :crypto.strong_rand_bytes(4800)
      frame = AudioFrame.new(audio_data, format: :pcm_16)

      converted = AudioFrame.convert_format(frame, :float32)
      assert converted.format == :float32
      assert byte_size(converted.data) == byte_size(frame.data) * 2  # float32 is 4 bytes vs 2 for pcm_16
    end

    test "detects silence" do
      # Create silent audio (all zeros)
      silent_data = <<0::size(4800 * 8)>>
      frame = AudioFrame.new(silent_data)

      assert AudioFrame.is_silence?(frame)

      # Create audio with some signal
      audio_data = :crypto.strong_rand_bytes(4800)
      frame = AudioFrame.new(audio_data)

      refute AudioFrame.is_silence?(frame)
    end

    test "splits stereo channels" do
      # Create stereo PCM16 data (left=100, right=200 repeated)
      stereo_data = for _i <- 1..100, into: <<>>, do: <<100::little-signed-16, 200::little-signed-16>>

      frame = AudioFrame.new(stereo_data, channels: 2, layout: :stereo)

      {:ok, [left, right]} = AudioFrame.split_channels(frame)

      assert left.channels == 1
      assert right.channels == 1
      assert left.layout == :mono
      assert right.layout == :mono
    end

    test "mixes multiple frames" do
      audio1 = :crypto.strong_rand_bytes(1000)
      audio2 = :crypto.strong_rand_bytes(1000)

      frame1 = AudioFrame.new(audio1)
      frame2 = AudioFrame.new(audio2)

      {:ok, mixed} = AudioFrame.mix([frame1, frame2])
      assert mixed.sample_rate == frame1.sample_rate
      assert mixed.channels == frame1.channels
    end
  end

  describe "WAV file handling" do
    test "handles invalid WAV data gracefully" do
      invalid_data = <<1, 2, 3, 4>>
      assert {:error, _} = AudioFrame.from_wav(invalid_data)
    end
  end
end
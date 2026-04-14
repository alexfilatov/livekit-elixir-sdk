defmodule Livekit.Agents.Pipeline.EnergyVADTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.AudioFrame
  alias Livekit.Agents.Pipeline.EnergyVAD

  # Build a PCM16 frame with a constant sample value (little-endian signed 16-bit)
  defp pcm16_frame(sample_value, sample_count \\ 160) do
    data = for _ <- 1..sample_count, into: <<>>, do: <<sample_value::little-signed-16>>
    AudioFrame.new(data, sample_rate: 16_000, channels: 1, format: :pcm_16)
  end

  # A frame whose RMS is clearly above 0.01 (loud audio)
  defp loud_frame, do: pcm16_frame(10_000)

  # A frame whose RMS is clearly below 0.01 (near-silence)
  defp silent_frame, do: pcm16_frame(0)

  describe "new/1" do
    test "returns a config struct with default threshold 0.01" do
      config = EnergyVAD.new(%{})
      assert config.threshold == 0.01
    end

    test "returns a config struct with the provided threshold" do
      config = EnergyVAD.new(%{threshold: 0.02})
      assert config.threshold == 0.02
    end
  end

  describe "classify/2" do
    test "returns :speech when AudioFrame.is_silence? is false" do
      config = EnergyVAD.new(%{})
      frame = loud_frame()
      refute AudioFrame.is_silence?(frame, config.threshold)
      assert EnergyVAD.classify(frame, config) == :speech
    end

    test "returns :silence when AudioFrame.is_silence? is true" do
      config = EnergyVAD.new(%{})
      frame = silent_frame()
      assert AudioFrame.is_silence?(frame, config.threshold)
      assert EnergyVAD.classify(frame, config) == :silence
    end

    test "passes config.threshold to AudioFrame.is_silence?/2" do
      # Use a very low threshold (0.0001) so a quiet frame is :speech
      config = EnergyVAD.new(%{threshold: 0.0001})
      # pcm16 sample 50 → RMS = 50/32768 ≈ 0.00153, above 0.0001 → :speech
      frame = pcm16_frame(50)
      assert EnergyVAD.classify(frame, config) == :speech

      # With the default threshold (0.01), same frame is :silence
      default_config = EnergyVAD.new(%{})
      assert EnergyVAD.classify(frame, default_config) == :silence
    end
  end
end

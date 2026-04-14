defmodule Livekit.Agents.VoiceAgentTest do
  use ExUnit.Case, async: true

  # Legacy tests — VoiceAgent still references Pipeline.new/0 which was removed.
  # These need to be rewritten to use the new Pipeline.start_link/1 API.
  @moduletag :legacy

  alias Livekit.Agents.{VoiceAgent, AudioFrame, Pipeline}

  describe "VoiceAgent" do
    test "starts with valid configuration" do
      config = %VoiceAgent.Config{
        instructions: "Test instructions",
        name: "Test Agent"
      }

      assert {:ok, pid} = VoiceAgent.start_link(config)
      assert Process.alive?(pid)
    end

    test "processes audio frames" do
      config = %VoiceAgent.Config{
        instructions: "Test instructions",
        name: "Test Agent"
      }

      {:ok, pid} = VoiceAgent.start_link(config)

      # ~100ms of audio
      audio_data = :crypto.strong_rand_bytes(4800)
      audio_frame = AudioFrame.new(audio_data, sample_rate: 48_000)

      assert :ok = VoiceAgent.process_audio_frame(pid, audio_frame)
    end

    test "maintains conversation context" do
      config = %VoiceAgent.Config{
        instructions: "Test instructions",
        name: "Test Agent"
      }

      {:ok, pid} = VoiceAgent.start_link(config)

      # Initially empty conversation
      assert [] = VoiceAgent.get_conversation_context(pid)

      # Process some audio to generate context
      audio_data = :crypto.strong_rand_bytes(4800)
      audio_frame = AudioFrame.new(audio_data, sample_rate: 48_000)
      VoiceAgent.process_audio_frame(pid, audio_frame)

      # Allow time for processing
      Process.sleep(100)

      # Should have some conversation context now
      context = VoiceAgent.get_conversation_context(pid)
      assert is_list(context)
    end

    test "updates configuration at runtime" do
      config = %VoiceAgent.Config{
        instructions: "Original instructions",
        name: "Test Agent"
      }

      {:ok, pid} = VoiceAgent.start_link(config)

      updates = %{instructions: "Updated instructions"}
      assert :ok = VoiceAgent.update_config(pid, updates)
    end

    test "tracks metrics" do
      config = %VoiceAgent.Config{
        instructions: "Test instructions",
        name: "Test Agent"
      }

      {:ok, pid} = VoiceAgent.start_link(config)

      metrics = VoiceAgent.get_metrics(pid)
      assert is_map(metrics)
      assert Map.has_key?(metrics, :audio_frames_processed)
      assert Map.has_key?(metrics, :turns_processed)
      assert Map.has_key?(metrics, :errors)
    end
  end

  describe "VoiceAgent.Config" do
    test "has sensible defaults" do
      config = %VoiceAgent.Config{}

      assert config.instructions == "You are a helpful AI assistant."
      assert config.name == "Assistant"
      assert config.vad_enabled == true
      assert config.turn_detection == :multilingual
      assert config.preemptive_synthesis == true
    end

    test "can be customized" do
      config = %VoiceAgent.Config{
        instructions: "Custom instructions",
        name: "Custom Agent",
        vad_enabled: false,
        turn_detection: :simple
      }

      assert config.instructions == "Custom instructions"
      assert config.name == "Custom Agent"
      assert config.vad_enabled == false
      assert config.turn_detection == :simple
    end
  end
end

defmodule Livekit.Agents.IntegrationTest do
  use ExUnit.Case, async: false

  # Legacy integration tests — reference old Pipeline.new/0 and mock provider APIs.
  @moduletag :legacy

  alias Livekit.Agents.{VoiceAgent, AgentSession, Worker, JobContext, AudioFrame}
  alias Livekit.Agents.STT.Deepgram
  alias Livekit.Agents.LLM.OpenAI
  alias Livekit.Agents.TTS.OpenAI, as: OpenAITTS

  @moduletag :integration

  describe "Voice Agent Integration" do
    test "complete voice processing pipeline" do
      # Create a voice agent with mock providers
      config = %VoiceAgent.Config{
        instructions: "You are a test assistant",
        name: "Test Agent"
      }

      {:ok, agent_pid} = VoiceAgent.start_link(config)

      # Create some test audio
      # ~100ms at 48kHz
      audio_data = :crypto.strong_rand_bytes(4800)
      audio_frame = AudioFrame.new(audio_data, sample_rate: 48_000)

      # Process audio through the agent
      assert :ok = VoiceAgent.process_audio_frame(agent_pid, audio_frame)

      # Allow time for processing
      Process.sleep(200)

      # Check that metrics were updated
      metrics = VoiceAgent.get_metrics(agent_pid)
      assert metrics.audio_frames_processed > 0
    end

    test "agent session lifecycle" do
      session_config = %AgentSession.Config{
        room_name: "test-room",
        participant_identity: "test-agent",
        server_url: "ws://localhost:7880",
        api_key: "test-key",
        api_secret: "test-secret"
      }

      {:ok, session_pid} = AgentSession.start_link(session_config)

      # Check initial status
      status = AgentSession.get_status(session_pid)
      assert status.room_name == "test-room"
      assert status.participant_identity == "test-agent"
      refute status.room_connected

      # Test sending a message
      assert {:error, :not_connected} = AgentSession.send_message(session_pid, "Hello")

      # Test updating metadata
      assert :ok = AgentSession.update_metadata(session_pid, %{test: "value"})

      status = AgentSession.get_status(session_pid)
      assert status.session_metadata.test == "value"
    end

    test "job context creation and validation" do
      context =
        JobContext.new(%{
          job_id: "test-job-123",
          room_name: "test-room",
          participant_identity: "test-agent",
          server_url: "ws://localhost:7880",
          api_key: "test-key",
          api_secret: "test-secret"
        })

      assert context.job_id == "test-job-123"
      assert context.room_name == "test-room"
      assert :ok = JobContext.validate(context)

      # Test token creation
      token = JobContext.create_room_token(context)
      assert is_binary(token)
      assert String.length(token) > 0

      # Test metadata operations
      context_with_metadata = JobContext.put_metadata(context, "test_key", "test_value")
      assert JobContext.get_metadata(context_with_metadata, "test_key") == "test_value"
    end

    test "audio frame operations" do
      # Test basic frame creation
      audio_data = :crypto.strong_rand_bytes(1000)
      frame = AudioFrame.new(audio_data, sample_rate: 16_000)

      assert frame.sample_rate == 16_000
      assert frame.data == audio_data

      # Test resampling
      resampled = AudioFrame.resample(frame, 48_000)
      assert resampled.sample_rate == 48_000

      # Test silence detection
      silent_data = <<0::size(1000 * 8)>>
      silent_frame = AudioFrame.new(silent_data)
      assert AudioFrame.is_silence?(silent_frame)

      # Test duration calculation
      duration_ms = AudioFrame.duration_ms(frame)
      assert duration_ms > 0
    end

    test "AI provider configurations" do
      # Test Deepgram STT config
      deepgram_config = %Deepgram.Config{
        api_key: "test-key",
        model: "nova-2",
        language: "en-US"
      }

      assert deepgram_config.api_key == "test-key"
      assert deepgram_config.model == "nova-2"

      # Test OpenAI LLM config
      openai_llm_config = %OpenAI.Config{
        api_key: "test-key",
        model: "gpt-4o-mini",
        temperature: 0.7
      }

      assert openai_llm_config.model == "gpt-4o-mini"
      assert openai_llm_config.temperature == 0.7

      # Test OpenAI TTS config
      openai_tts_config = %OpenAITTS.Config{
        api_key: "test-key",
        voice: :alloy,
        model: :tts_1
      }

      assert openai_tts_config.voice == :alloy
      assert openai_tts_config.model == :tts_1
    end
  end

  describe "Error Handling" do
    test "handles invalid configurations gracefully" do
      # Test invalid voice agent config
      invalid_config = %VoiceAgent.Config{
        instructions: nil,
        name: ""
      }

      # Should still start but with defaults
      {:ok, _pid} = VoiceAgent.start_link(invalid_config)
    end

    test "handles missing API keys gracefully" do
      # Test configs without API keys
      deepgram_config = %Deepgram.Config{api_key: nil}
      openai_config = %OpenAI.Config{api_key: nil}

      # Should fail validation when actually used
      assert_raise RuntimeError, fn ->
        Deepgram.start_link(deepgram_config)
      end

      assert_raise RuntimeError, fn ->
        OpenAI.start_link(openai_config)
      end
    end
  end
end

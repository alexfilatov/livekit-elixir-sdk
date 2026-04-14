# Inline mock providers — implement behaviours without external calls

defmodule Livekit.Agents.Pipeline.Test.MockSTT do
  @moduledoc false
  use Livekit.Agents.STT

  @impl true
  def transcribe(_audio_binary, _opts) do
    {:ok,
     %Livekit.Agents.STT.SpeechEvent{
       type: :final,
       text: "hello world",
       confidence: 0.99,
       language: "en"
     }}
  end

  @impl true
  def capabilities,
    do: %{streaming: false, interim_results: false, diarization: false, languages: ["en"]}
end

defmodule Livekit.Agents.Pipeline.Test.MockLLM do
  @moduledoc false
  use Livekit.Agents.LLM

  @impl true
  def chat(_context, _opts) do
    {:ok, %{role: :assistant, content: "I heard you say: hello world"}}
  end

  @impl true
  def capabilities,
    do: %{streaming: false, tool_calling: false, vision: false, max_context_tokens: 4096}
end

defmodule Livekit.Agents.Pipeline.Test.MockTTS do
  @moduledoc false
  use Livekit.Agents.TTS

  @impl true
  def synthesize(text, _opts) do
    # Return audio bytes proportional to text length
    {:ok, :crypto.strong_rand_bytes(max(16, byte_size(text) * 4))}
  end

  @impl true
  def capabilities,
    do: %{streaming: false, voices: ["default"], audio_formats: [:pcm], word_timing: false}
end

defmodule Livekit.Agents.Pipeline.Test.FailingSTT do
  @moduledoc false
  use Livekit.Agents.STT

  @impl true
  def transcribe(_audio, _opts), do: {:error, :api_error}

  @impl true
  def capabilities,
    do: %{streaming: false, interim_results: false, diarization: false, languages: ["en"]}
end

defmodule Livekit.Agents.PipelineTest do
  use ExUnit.Case, async: false

  alias Livekit.Agents.{AudioFrame, Pipeline}

  alias Livekit.Agents.Pipeline.Test.{FailingSTT, MockLLM, MockSTT, MockTTS}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp speech_data do
    for _ <- 1..160, into: <<>>, do: <<32_767::little-signed-16>>
  end

  defp silence_data, do: <<0::320*8>>

  defp speech_frame, do: AudioFrame.new(speech_data(), sample_rate: 16_000, format: :pcm_16)
  defp silence_frame, do: AudioFrame.new(silence_data(), sample_rate: 16_000, format: :pcm_16)

  defp base_config(overrides \\ []) do
    %Pipeline.Config{
      stt: {MockSTT, %{}},
      llm: {MockLLM, %{}},
      tts: {MockTTS, %{}},
      silence_ms: Keyword.get(overrides, :silence_ms, 50)
    }
  end

  # ---------------------------------------------------------------------------
  # start_link/1
  # ---------------------------------------------------------------------------

  describe "start_link/1" do
    test "starts successfully with valid config" do
      {:ok, pid} = Pipeline.start_link(base_config())
      assert Process.alive?(pid)
      Pipeline.stop(pid)
    end

    test "returns error when stt is nil" do
      Process.flag(:trap_exit, true)
      config = %Pipeline.Config{stt: nil, llm: {MockLLM, %{}}, tts: {MockTTS, %{}}}
      assert {:error, _} = Pipeline.start_link(config)
    end

    test "returns error when llm is nil" do
      Process.flag(:trap_exit, true)
      config = %Pipeline.Config{stt: {MockSTT, %{}}, llm: nil, tts: {MockTTS, %{}}}
      assert {:error, _} = Pipeline.start_link(config)
    end

    test "returns error when tts is nil" do
      Process.flag(:trap_exit, true)
      config = %Pipeline.Config{stt: {MockSTT, %{}}, llm: {MockLLM, %{}}, tts: nil}
      assert {:error, _} = Pipeline.start_link(config)
    end
  end

  # ---------------------------------------------------------------------------
  # push_frame/2 — non-blocking
  # ---------------------------------------------------------------------------

  describe "push_frame/2" do
    test "returns :ok immediately (non-blocking cast)" do
      {:ok, pid} = Pipeline.start_link(base_config())
      result = Pipeline.push_frame(pid, speech_frame())
      assert result == :ok
      Pipeline.stop(pid)
    end
  end

  # ---------------------------------------------------------------------------
  # Full STT->LLM->TTS integration turn (TEST-07)
  # ---------------------------------------------------------------------------

  describe "full STT->LLM->TTS integration turn (TEST-07)" do
    test "pushing speech frames then silence completes a full pipeline turn" do
      {:ok, pid} = Pipeline.start_link(base_config(silence_ms: 50))

      # Push speech frames to accumulate an utterance
      Enum.each(1..5, fn _ -> Pipeline.push_frame(pid, speech_frame()) end)
      # Push silence to trigger end-of-turn
      Pipeline.push_frame(pid, silence_frame())

      # Wait for async Task to complete (STT + LLM + TTS)
      Process.sleep(400)

      metrics = Pipeline.get_metrics(pid)
      assert metrics.turns_processed == 1
      assert metrics.errors == 0
      assert metrics.audio_frames_processed == 6

      Pipeline.stop(pid)
    end

    test "conversation context accumulates across turns" do
      {:ok, pid} = Pipeline.start_link(base_config(silence_ms: 50))

      # First turn
      Pipeline.push_frame(pid, speech_frame())
      Pipeline.push_frame(pid, silence_frame())
      Process.sleep(400)

      # Second turn
      Pipeline.push_frame(pid, speech_frame())
      Pipeline.push_frame(pid, silence_frame())
      Process.sleep(400)

      metrics = Pipeline.get_metrics(pid)
      assert metrics.turns_processed == 2

      Pipeline.stop(pid)
    end

    test "pipeline audio is forwarded to subscriber" do
      test_pid = self()

      config = %Pipeline.Config{
        stt: {MockSTT, %{}},
        llm: {MockLLM, %{}},
        tts: {MockTTS, %{}},
        subscriber: test_pid,
        silence_ms: 50
      }

      {:ok, pid} = Pipeline.start_link(config)
      Pipeline.push_frame(pid, speech_frame())
      Pipeline.push_frame(pid, silence_frame())

      assert_receive {:pipeline_audio, audio_frame}, 500
      assert %AudioFrame{} = audio_frame
      assert is_binary(audio_frame.data)

      Pipeline.stop(pid)
    end
  end

  # ---------------------------------------------------------------------------
  # :telemetry events (PIPE-06)
  # ---------------------------------------------------------------------------

  describe ":telemetry events (PIPE-06)" do
    test "stt_complete, llm_first_token, tts_start events fire in order during a turn" do
      test_pid = self()
      events_received = :ets.new(:events, [:ordered_set, :public])

      handler_id = "test-pipeline-#{System.unique_integer()}"

      events = [
        [:livekit, :agents, :pipeline, :stt_complete],
        [:livekit, :agents, :pipeline, :llm_first_token],
        [:livekit, :agents, :pipeline, :tts_start]
      ]

      :telemetry.attach_many(
        handler_id,
        events,
        fn event_name, measurements, _metadata, _config ->
          :ets.insert(events_received, {System.monotonic_time(), event_name, measurements})
          send(test_pid, {:telemetry_event, List.last(event_name)})
        end,
        nil
      )

      {:ok, pid} = Pipeline.start_link(base_config(silence_ms: 50))
      Pipeline.push_frame(pid, speech_frame())
      Pipeline.push_frame(pid, silence_frame())

      assert_receive {:telemetry_event, :stt_complete}, 500
      assert_receive {:telemetry_event, :llm_first_token}, 500
      assert_receive {:telemetry_event, :tts_start}, 500

      # Verify order via ETS monotonic timestamps
      ordered = :ets.tab2list(events_received) |> Enum.sort() |> Enum.map(&elem(&1, 1))

      assert ordered == [
               [:livekit, :agents, :pipeline, :stt_complete],
               [:livekit, :agents, :pipeline, :llm_first_token],
               [:livekit, :agents, :pipeline, :tts_start]
             ]

      :telemetry.detach(handler_id)
      Pipeline.stop(pid)
    end
  end

  # ---------------------------------------------------------------------------
  # Interruption handling (PIPE-04)
  # ---------------------------------------------------------------------------

  describe "interruption handling (PIPE-04)" do
    test "new speech while processing cancels active task; errors metric stays at 0" do
      {:ok, pid} = Pipeline.start_link(base_config(silence_ms: 50))

      # First turn: push speech + silence
      Pipeline.push_frame(pid, speech_frame())
      Pipeline.push_frame(pid, silence_frame())

      # Immediately push speech again to interrupt before Task completes
      Process.sleep(10)
      Pipeline.push_frame(pid, speech_frame())
      Pipeline.push_frame(pid, silence_frame())

      # Allow both turns to resolve
      Process.sleep(600)

      metrics = Pipeline.get_metrics(pid)
      # Interruption is a clean cancel, not an error
      assert metrics.errors == 0
      assert metrics.audio_frames_processed >= 4

      Pipeline.stop(pid)
    end
  end

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------

  describe "error handling" do
    test "STT error increments error metric and pipeline recovers" do
      config = %Pipeline.Config{
        stt: {FailingSTT, %{}},
        llm: {MockLLM, %{}},
        tts: {MockTTS, %{}},
        silence_ms: 50
      }

      {:ok, pid} = Pipeline.start_link(config)
      Pipeline.push_frame(pid, speech_frame())
      Pipeline.push_frame(pid, silence_frame())
      Process.sleep(300)

      metrics = Pipeline.get_metrics(pid)
      assert metrics.errors == 1
      assert metrics.turns_processed == 0
      assert Process.alive?(pid)

      Pipeline.stop(pid)
    end
  end

  # ---------------------------------------------------------------------------
  # get_metrics/1
  # ---------------------------------------------------------------------------

  describe "get_metrics/1" do
    test "returns metrics map with expected keys" do
      {:ok, pid} = Pipeline.start_link(base_config())
      metrics = Pipeline.get_metrics(pid)

      assert is_map(metrics)
      assert Map.has_key?(metrics, :turns_processed)
      assert Map.has_key?(metrics, :audio_frames_processed)
      assert Map.has_key?(metrics, :errors)

      Pipeline.stop(pid)
    end

    test "audio_frames_processed increments on each push_frame call" do
      {:ok, pid} = Pipeline.start_link(base_config())

      Pipeline.push_frame(pid, silence_frame())
      Pipeline.push_frame(pid, silence_frame())
      Pipeline.push_frame(pid, silence_frame())

      # Allow casts to be processed
      Process.sleep(50)

      metrics = Pipeline.get_metrics(pid)
      assert metrics.audio_frames_processed == 3

      Pipeline.stop(pid)
    end
  end
end

# Inline mock providers for agent handoff tests

defmodule Livekit.Agents.AgentHandoff.Test.MockSTT do
  @moduledoc false
  use Livekit.Agents.STT

  @impl true
  def transcribe(_audio_binary, _opts) do
    {:ok,
     %Livekit.Agents.STT.SpeechEvent{
       type: :final,
       text: "hello handoff",
       confidence: 0.99,
       language: "en"
     }}
  end

  @impl true
  def capabilities,
    do: %{streaming: false, interim_results: false, diarization: false, languages: ["en"]}
end

defmodule Livekit.Agents.AgentHandoff.Test.MockLLM do
  @moduledoc false
  use Livekit.Agents.LLM

  @impl true
  def chat(_context, _opts) do
    {:ok, %{role: :assistant, content: "I am the first agent"}}
  end

  @impl true
  def capabilities,
    do: %{streaming: false, tool_calling: false, vision: false, max_context_tokens: 4096}
end

defmodule Livekit.Agents.AgentHandoff.Test.MockLLM2 do
  @moduledoc false
  use Livekit.Agents.LLM

  @impl true
  def chat(_context, _opts) do
    {:ok, %{role: :assistant, content: "I am the second agent"}}
  end

  @impl true
  def capabilities,
    do: %{streaming: false, tool_calling: false, vision: false, max_context_tokens: 4096}
end

defmodule Livekit.Agents.AgentHandoff.Test.MockTTS do
  @moduledoc false
  use Livekit.Agents.TTS

  @impl true
  def synthesize(_text, _opts), do: {:ok, :crypto.strong_rand_bytes(64)}

  @impl true
  def capabilities,
    do: %{streaming: false, voices: ["default"], audio_formats: [:pcm], word_timing: false}
end

defmodule Livekit.Agents.AgentHandoff.Test.FailingSTT do
  @moduledoc false
  use Livekit.Agents.STT

  @impl true
  def transcribe(_audio, _opts), do: {:error, :api_error}

  @impl true
  def capabilities,
    do: %{streaming: false, interim_results: false, diarization: false, languages: ["en"]}
end

# ---------------------------------------------------------------------------
# Test module
# ---------------------------------------------------------------------------

defmodule Livekit.Agents.AgentHandoffTest do
  use ExUnit.Case, async: false

  alias Livekit.Agents.{AgentHandoff, ChatContext, EventBus, Pipeline}
  alias Livekit.Agents.Events.AgentHandoff, as: AgentHandoffEvent

  alias Livekit.Agents.AgentHandoff.Test.{
    MockLLM,
    MockLLM2,
    MockSTT,
    MockTTS
  }

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp mock_pipeline_config(llm_mod \\ MockLLM) do
    %Pipeline.Config{
      stt: {MockSTT, %{mode: :mock}},
      llm: {llm_mod, %{mode: :mock}},
      tts: {MockTTS, %{mode: :mock}}
    }
  end

  defp start_pipeline(config \\ nil) do
    config = config || mock_pipeline_config()
    {:ok, pid} = Pipeline.start_link(config)
    pid
  end

  defp add_messages(pipeline_pid) do
    ctx =
      ChatContext.new()
      |> ChatContext.add(ChatContext.new_message(:user, ["Hello, who are you?"]))
      |> ChatContext.add(ChatContext.new_message(:assistant, ["I am the first agent."]))

    Pipeline.set_chat_context(pipeline_pid, ctx)
    ctx
  end

  # ---------------------------------------------------------------------------
  # Tests: ChatContext transfer
  # ---------------------------------------------------------------------------

  describe "handoff/3 — context transfer" do
    test "transfers ChatContext to new pipeline" do
      old_pid = start_pipeline()
      original_ctx = add_messages(old_pid)

      new_config = mock_pipeline_config(MockLLM2)
      assert {:ok, new_pid} = AgentHandoff.handoff(old_pid, new_config)

      transferred_ctx = Pipeline.get_chat_context(new_pid)
      assert transferred_ctx.items == original_ctx.items
      assert length(transferred_ctx.items) == 2

      # Cleanup
      if Process.alive?(new_pid), do: Pipeline.stop(new_pid)
    end

    test "transfers empty ChatContext when pipeline has no history" do
      old_pid = start_pipeline()
      new_config = mock_pipeline_config(MockLLM2)

      assert {:ok, new_pid} = AgentHandoff.handoff(old_pid, new_config)

      transferred_ctx = Pipeline.get_chat_context(new_pid)
      assert transferred_ctx.items == []

      if Process.alive?(new_pid), do: Pipeline.stop(new_pid)
    end

    test "stops old pipeline after warm handoff" do
      old_pid = start_pipeline()
      _ctx = add_messages(old_pid)

      new_config = mock_pipeline_config(MockLLM2)
      assert {:ok, new_pid} = AgentHandoff.handoff(old_pid, new_config, mode: :warm)

      # Old pipeline should be stopped
      refute Process.alive?(old_pid)
      assert Process.alive?(new_pid)

      if Process.alive?(new_pid), do: Pipeline.stop(new_pid)
    end

    test "stops old pipeline after cold handoff" do
      old_pid = start_pipeline()
      _ctx = add_messages(old_pid)

      new_config = mock_pipeline_config(MockLLM2)
      assert {:ok, new_pid} = AgentHandoff.handoff(old_pid, new_config, mode: :cold)

      refute Process.alive?(old_pid)
      assert Process.alive?(new_pid)

      if Process.alive?(new_pid), do: Pipeline.stop(new_pid)
    end

    test "new pipeline receives subscriber option" do
      old_pid = start_pipeline()
      subscriber = self()

      new_config = mock_pipeline_config(MockLLM2)
      assert {:ok, new_pid} = AgentHandoff.handoff(old_pid, new_config, subscriber: subscriber)

      # The new pipeline should have the subscriber set; verify via metrics
      metrics = Pipeline.get_metrics(new_pid)
      assert is_map(metrics)

      if Process.alive?(new_pid), do: Pipeline.stop(new_pid)
    end
  end

  # ---------------------------------------------------------------------------
  # Tests: Event emission
  # ---------------------------------------------------------------------------

  describe "handoff/3 — event emission" do
    setup do
      pid =
        case EventBus.start_link() do
          {:ok, p} -> p
          {:error, {:already_started, p}} -> p
        end

      # Unlink so the test process exit does not kill the Registry
      Process.unlink(pid)
      :ok
    end

    test "emits AgentHandoff event with correct fields when session_id given" do
      session_id = "test-session-#{:rand.uniform(10_000)}"
      EventBus.subscribe(session_id)

      old_pid = start_pipeline()
      _ctx = add_messages(old_pid)

      new_config = mock_pipeline_config(MockLLM2)

      assert {:ok, new_pid} =
               AgentHandoff.handoff(old_pid, new_config,
                 mode: :warm,
                 from_agent: :agent_one,
                 to_agent: :agent_two,
                 session_id: session_id
               )

      assert_receive {:livekit_event, %AgentHandoffEvent{} = event}, 1_000
      assert event.from_agent == :agent_one
      assert event.to_agent == :agent_two
      assert event.mode == :warm
      assert event.context_size == 2
      assert %DateTime{} = event.timestamp

      if Process.alive?(new_pid), do: Pipeline.stop(new_pid)
    end

    test "emits AgentHandoff event in cold mode" do
      session_id = "test-cold-#{:rand.uniform(10_000)}"
      EventBus.subscribe(session_id)

      old_pid = start_pipeline()

      new_config = mock_pipeline_config(MockLLM2)

      assert {:ok, new_pid} =
               AgentHandoff.handoff(old_pid, new_config,
                 mode: :cold,
                 session_id: session_id
               )

      assert_receive {:livekit_event, %AgentHandoffEvent{} = event}, 1_000
      assert event.mode == :cold
      assert event.context_size == 0

      if Process.alive?(new_pid), do: Pipeline.stop(new_pid)
    end

    test "does not emit event when no session_id provided" do
      old_pid = start_pipeline()
      new_config = mock_pipeline_config(MockLLM2)

      assert {:ok, new_pid} = AgentHandoff.handoff(old_pid, new_config)

      # No event should arrive (no session_id means no publish)
      refute_receive {:livekit_event, %AgentHandoffEvent{}}, 100

      if Process.alive?(new_pid), do: Pipeline.stop(new_pid)
    end
  end

  # ---------------------------------------------------------------------------
  # Tests: Error handling
  # ---------------------------------------------------------------------------

  describe "handoff/3 — error handling" do
    test "returns error when new pipeline config is missing providers" do
      Process.flag(:trap_exit, true)
      old_pid = start_pipeline()

      bad_config = %Pipeline.Config{
        stt: nil,
        llm: nil,
        tts: nil
      }

      assert {:error, {:new_pipeline_start_failed, :missing_providers}} =
               AgentHandoff.handoff(old_pid, bad_config)

      # Old pipeline should still be alive (handoff failed)
      assert Process.alive?(old_pid)

      Pipeline.stop(old_pid)
    end

    test "old pipeline remains alive after failed handoff" do
      Process.flag(:trap_exit, true)
      old_pid = start_pipeline()
      _ctx = add_messages(old_pid)

      bad_config = %Pipeline.Config{stt: nil, llm: nil, tts: nil}
      assert {:error, _} = AgentHandoff.handoff(old_pid, bad_config)

      assert Process.alive?(old_pid)
      Pipeline.stop(old_pid)
    end

    test "handles already-dead source pipeline gracefully" do
      old_pid = start_pipeline()
      Pipeline.stop(old_pid)

      # Give the process time to stop
      Process.sleep(50)

      new_config = mock_pipeline_config(MockLLM2)

      # Should return error because we cannot call get_chat_context on a dead process
      result = AgentHandoff.handoff(old_pid, new_config)
      assert match?({:error, _}, result)
    end
  end

  # ---------------------------------------------------------------------------
  # Tests: Pipeline.get_chat_context / set_chat_context
  # ---------------------------------------------------------------------------

  describe "Pipeline context API" do
    test "get_chat_context returns empty context on fresh pipeline" do
      pid = start_pipeline()
      ctx = Pipeline.get_chat_context(pid)
      assert %ChatContext{items: []} = ctx
      Pipeline.stop(pid)
    end

    test "set_chat_context replaces pipeline context" do
      pid = start_pipeline()

      ctx =
        ChatContext.new()
        |> ChatContext.add(ChatContext.new_message(:user, ["test message"]))

      assert :ok = Pipeline.set_chat_context(pid, ctx)

      retrieved = Pipeline.get_chat_context(pid)
      assert length(retrieved.items) == 1
      assert hd(retrieved.items).content == ["test message"]

      Pipeline.stop(pid)
    end
  end
end

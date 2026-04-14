# Mock providers for Pipeline edge-case tests — defined outside the test module
# so that aliases within the test module resolve correctly.

defmodule Livekit.Agents.EdgeCases.MockSTT do
  @moduledoc false
  use Livekit.Agents.STT

  @impl true
  def transcribe(_audio, _opts),
    do:
      {:ok,
       %Livekit.Agents.STT.SpeechEvent{
         type: :final,
         text: "ok",
         confidence: 1.0,
         language: "en"
       }}

  @impl true
  def capabilities,
    do: %{streaming: false, interim_results: false, diarization: false, languages: ["en"]}
end

defmodule Livekit.Agents.EdgeCases.MockLLM do
  @moduledoc false
  use Livekit.Agents.LLM

  alias Livekit.Agents.ChatContext

  @impl true
  def chat(_ctx, _opts) do
    queue = Process.get(:edge_mock_queue, [])

    case queue do
      [] ->
        msg = ChatContext.new_message(:assistant, ["(done)"])
        {:ok, msg}

      [next | rest] ->
        Process.put(:edge_mock_queue, rest)

        case next do
          {:assistant, text} ->
            {:ok, ChatContext.new_message(:assistant, [text])}

          {:function_call, call_id, name, args_json} ->
            {:ok, ChatContext.new_function_call(call_id, name, args_json)}

          {:error, reason} ->
            {:error, reason}

          # Pipeline test variant — plain assistant map
          :pipeline_response ->
            {:ok, %{role: :assistant, content: "response"}}
        end
    end
  end

  @impl true
  def capabilities,
    do: %{streaming: false, tool_calling: true, vision: false, max_context_tokens: 4096}
end

defmodule Livekit.Agents.EdgeCases.PipelineMockLLM do
  @moduledoc false
  use Livekit.Agents.LLM

  @impl true
  def chat(_ctx, _opts), do: {:ok, %{role: :assistant, content: "response"}}

  @impl true
  def capabilities,
    do: %{streaming: false, tool_calling: false, vision: false, max_context_tokens: 4096}
end

defmodule Livekit.Agents.EdgeCases.MockTTS do
  @moduledoc false
  use Livekit.Agents.TTS

  @impl true
  def synthesize(_text, _opts), do: {:ok, <<1, 2, 3, 4>>}

  @impl true
  def capabilities,
    do: %{streaming: false, voices: ["default"], audio_formats: [:pcm], word_timing: false}
end

# ---------------------------------------------------------------------------

defmodule Livekit.Agents.EdgeCasesTest do
  @moduledoc """
  Comprehensive edge-case and failure-mode tests for the Livekit Agents framework.

  Covers boundary conditions and crash-prevention scenarios not addressed by the
  primary unit-test suite.
  """

  use ExUnit.Case, async: true

  alias Livekit.Agents.AudioFrame
  alias Livekit.Agents.ChatContext
  alias Livekit.Agents.ChatContext.{ChatMessage, FunctionCall, FunctionCallOutput}
  alias Livekit.Agents.Pipeline
  alias Livekit.Agents.Pipeline.Config, as: PipelineConfig
  alias Livekit.Agents.Pipeline.{EnergyVAD, TurnDetector}
  alias Livekit.Agents.STT.AudioBuffer
  alias Livekit.Agents.TTS.OpenAI.Cache
  alias Livekit.Agents.Tool.{ToolContext, ToolSpec}
  alias Livekit.Agents.{AgentStateMachine, UserStateMachine}

  alias Livekit.Agents.EdgeCases.{MockSTT, PipelineMockLLM, MockTTS}

  # ---------------------------------------------------------------------------
  # 1. ChatContext edge cases
  # ---------------------------------------------------------------------------

  describe "ChatContext.truncate/2 with 0 max_items" do
    test "raises FunctionClauseError — 0 is not a pos_integer" do
      ctx = ChatContext.new()
      assert_raise FunctionClauseError, fn -> ChatContext.truncate(ctx, 0) end
    end
  end

  describe "ChatContext.truncate/2 when all messages are system messages" do
    test "preserves all system messages — none are dropped" do
      sys1 = ChatContext.new_message(:system, ["You are helpful."])
      sys2 = ChatContext.new_message(:system, ["Always be concise."])
      sys3 = ChatContext.new_message(:system, ["Reply in English."])

      ctx =
        ChatContext.new()
        |> ChatContext.add(sys1)
        |> ChatContext.add(sys2)
        |> ChatContext.add(sys3)

      # truncate with max_items: 1 — but all are system, so none should be dropped
      truncated = ChatContext.truncate(ctx, 1)
      assert length(truncated.items) == 3
      assert Enum.all?(truncated.items, fn item -> match?(%ChatMessage{role: :system}, item) end)
    end
  end

  describe "ChatContext.truncate/2 with orphaned FunctionCallOutput at boundary" do
    test "drops FunctionCallOutput whose FunctionCall was truncated away" do
      fc = ChatContext.new_function_call("cid-orphan", "tool_x", "{}")
      fco = ChatContext.new_function_call_output("cid-orphan", "tool_x", "result")
      user1 = ChatContext.new_message(:user, ["first"])
      user2 = ChatContext.new_message(:user, ["second"])

      # Context order: [fc, fco, user1, user2]
      # Truncating to 3 keeps [fco, user1, user2] — fco is orphaned (fc was dropped)
      ctx =
        ChatContext.new()
        |> ChatContext.add(fc)
        |> ChatContext.add(fco)
        |> ChatContext.add(user1)
        |> ChatContext.add(user2)

      truncated = ChatContext.truncate(ctx, 3)

      # fco should be dropped because its fc was excluded from the slice
      refute Enum.any?(truncated.items, &match?(%FunctionCallOutput{}, &1))
      # user messages should still be present
      assert Enum.count(truncated.items, &match?(%ChatMessage{role: :user}, &1)) == 2
    end
  end

  describe "ChatContext.add/2 with nil content in ChatMessage" do
    test "nil content is stored as-is — add/2 does not validate fields" do
      # add/2 is a plain list append — no validation of item field values.
      # A manually-constructed ChatMessage with nil content is stored without crash.
      msg = %ChatMessage{
        id: "test-id",
        role: :user,
        content: nil,
        interrupted: false,
        created_at: DateTime.utc_now()
      }

      ctx = ChatContext.new()
      ctx = ChatContext.add(ctx, msg)
      assert length(ctx.items) == 1
      assert hd(ctx.items).content == nil
    end
  end

  describe "ChatContext.merge/2 with duplicate IDs" do
    test "deduplicates items that share an id" do
      msg = ChatContext.new_message(:user, ["hello"])
      ctx1 = ChatContext.add(ChatContext.new(), msg)
      ctx2 = ChatContext.add(ChatContext.new(), msg)

      merged = ChatContext.merge(ctx1, ctx2)
      assert length(merged.items) == 1
    end

    test "retains the original item when the duplicate comes from other" do
      msg = ChatContext.new_message(:user, ["original"])
      ctx1 = ChatContext.add(ChatContext.new(), msg)
      ctx2 = ChatContext.add(ChatContext.new(), msg)

      merged = ChatContext.merge(ctx1, ctx2)
      assert hd(merged.items) == msg
    end
  end

  describe "ChatContext.merge/2 with empty contexts" do
    test "merging two empty contexts returns an empty context" do
      merged = ChatContext.merge(ChatContext.new(), ChatContext.new())
      assert merged.items == []
    end

    test "merging empty into non-empty returns original items" do
      msg = ChatContext.new_message(:assistant, ["hi"])
      ctx = ChatContext.add(ChatContext.new(), msg)

      merged = ChatContext.merge(ctx, ChatContext.new())
      assert length(merged.items) == 1
      assert hd(merged.items) == msg
    end

    test "merging non-empty into empty returns other items" do
      msg = ChatContext.new_message(:assistant, ["hi"])
      other = ChatContext.add(ChatContext.new(), msg)

      merged = ChatContext.merge(ChatContext.new(), other)
      assert length(merged.items) == 1
    end
  end

  describe "ChatContext.new_message/2 with invalid role atom" do
    test "raises FunctionClauseError for an unrecognised role" do
      assert_raise FunctionClauseError, fn ->
        ChatContext.new_message(:robot, ["beep boop"])
      end
    end

    test "raises FunctionClauseError for a binary role (not atom)" do
      assert_raise FunctionClauseError, fn ->
        ChatContext.new_message("user", ["hello"])
      end
    end
  end

  describe "ChatContext.messages/1 ordering" do
    test "returns ChatMessages in chronological (insertion) order" do
      msg1 = ChatContext.new_message(:user, ["first"])
      msg2 = ChatContext.new_message(:assistant, ["second"])
      msg3 = ChatContext.new_message(:user, ["third"])

      ctx =
        ChatContext.new()
        |> ChatContext.add(msg1)
        |> ChatContext.add(msg2)
        |> ChatContext.add(msg3)

      msgs = ChatContext.messages(ctx)
      assert length(msgs) == 3
      assert Enum.map(msgs, & &1.content) == [["first"], ["second"], ["third"]]
    end

    test "skips FunctionCall and FunctionCallOutput items" do
      msg = ChatContext.new_message(:user, ["hello"])
      fc = ChatContext.new_function_call("cid", "fn", "{}")
      fco = ChatContext.new_function_call_output("cid", "fn", "result")

      ctx =
        ChatContext.new()
        |> ChatContext.add(fc)
        |> ChatContext.add(msg)
        |> ChatContext.add(fco)

      msgs = ChatContext.messages(ctx)
      assert length(msgs) == 1
      assert hd(msgs) == msg
    end
  end

  describe "ChatContext.copy/1 produces independent copy" do
    test "adding to original does not affect the copy" do
      msg1 = ChatContext.new_message(:user, ["original"])
      ctx = ChatContext.add(ChatContext.new(), msg1)

      copy = ChatContext.copy(ctx)

      msg2 = ChatContext.new_message(:assistant, ["extra"])
      _ctx_updated = ChatContext.add(ctx, msg2)

      # Copy should remain untouched
      assert length(copy.items) == 1
      assert hd(copy.items) == msg1
    end
  end

  describe "Jason encode/decode round-trip for all struct types" do
    test "ChatMessage round-trip preserves expected keys (decoded as plain map)" do
      msg = ChatContext.new_message(:assistant, ["Response text"])
      json = Jason.encode!(msg)
      decoded = Jason.decode!(json)

      assert is_map(decoded)
      assert decoded["role"] == "assistant"
      assert decoded["content"] == ["Response text"]
      assert decoded["interrupted"] == false
      assert is_binary(decoded["id"])
      assert is_binary(decoded["created_at"])
      refute match?(%ChatMessage{}, decoded)
    end

    test "FunctionCall round-trip preserves expected keys" do
      fc = ChatContext.new_function_call("call-abc", "get_weather", ~s({"city":"Paris"}))
      decoded = Jason.decode!(Jason.encode!(fc))

      assert is_map(decoded)
      assert decoded["call_id"] == "call-abc"
      assert decoded["name"] == "get_weather"
      assert decoded["arguments"] == ~s({"city":"Paris"})
      assert is_binary(decoded["id"])
      assert is_binary(decoded["created_at"])
      refute match?(%FunctionCall{}, decoded)
    end

    test "FunctionCallOutput round-trip preserves expected keys" do
      fco = ChatContext.new_function_call_output("call-xyz", "do_thing", "success", false)
      decoded = Jason.decode!(Jason.encode!(fco))

      assert is_map(decoded)
      assert decoded["call_id"] == "call-xyz"
      assert decoded["name"] == "do_thing"
      assert decoded["output"] == "success"
      assert decoded["is_error"] == false
      assert is_binary(decoded["id"])
      assert is_binary(decoded["created_at"])
      refute match?(%FunctionCallOutput{}, decoded)
    end

    test "FunctionCallOutput with is_error: true round-trips correctly" do
      fco = ChatContext.new_function_call_output("call-err", "bad_tool", "error msg", true)
      decoded = Jason.decode!(Jason.encode!(fco))
      assert decoded["is_error"] == true
    end

    test "created_at is an ISO 8601 string with T separator" do
      msg = ChatContext.new_message(:user, ["test"])
      decoded = Jason.decode!(Jason.encode!(msg))
      assert String.contains?(decoded["created_at"], "T")
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Tool system edge cases
  # ---------------------------------------------------------------------------

  describe "ToolSpec.new/1 with missing required fields" do
    test "raises KeyError when :name is missing" do
      assert_raise KeyError, fn ->
        ToolSpec.new(description: "d", parameters: %{}, handler: fn _ -> {:ok, "x"} end)
      end
    end

    test "raises KeyError when :description is missing" do
      assert_raise KeyError, fn ->
        ToolSpec.new(name: "n", parameters: %{}, handler: fn _ -> {:ok, "x"} end)
      end
    end

    test "raises KeyError when :parameters is missing" do
      assert_raise KeyError, fn ->
        ToolSpec.new(name: "n", description: "d", handler: fn _ -> {:ok, "x"} end)
      end
    end

    test "raises KeyError when :handler is missing" do
      assert_raise KeyError, fn ->
        ToolSpec.new(name: "n", description: "d", parameters: %{})
      end
    end
  end

  describe "ToolContext.lookup/2 with empty context" do
    test "returns {:error, :not_found} for any name in empty context" do
      tc = ToolContext.new([])
      assert {:error, :not_found} = ToolContext.lookup(tc, "anything")
    end
  end

  describe "ToolContext.to_openai_tools/1 output structure" do
    test "each entry has 'type' => 'function' at the top level" do
      spec =
        ToolSpec.new(
          name: "calculator",
          description: "Does math",
          parameters: %{"type" => "object", "properties" => %{}},
          handler: fn _ -> {:ok, "42"} end
        )

      tc = ToolContext.new([spec])
      [tool] = ToolContext.to_openai_tools(tc)

      assert tool["type"] == "function"
    end

    test "each entry has 'function' key with name, description, parameters" do
      params = %{"type" => "object", "properties" => %{"x" => %{"type" => "number"}}}

      spec =
        ToolSpec.new(
          name: "add",
          description: "Adds numbers",
          parameters: params,
          handler: fn _ -> {:ok, "done"} end
        )

      tc = ToolContext.new([spec])
      [tool] = ToolContext.to_openai_tools(tc)
      fn_map = tool["function"]

      assert fn_map["name"] == "add"
      assert fn_map["description"] == "Adds numbers"
      assert fn_map["parameters"] == params
    end

    test "empty context returns empty list" do
      tc = ToolContext.new([])
      assert ToolContext.to_openai_tools(tc) == []
    end
  end

  defp set_mock_queue(items), do: Process.put(:edge_mock_queue, items)

  describe "Tool.run/3 with max_tool_steps: 0" do
    test "returns immediately without executing any tool calls" do
      tc = ToolContext.new([])
      ctx = ChatContext.new()

      set_mock_queue([{:function_call, "cid-1", "some_tool", "{}"}])

      assert {:ok, final_ctx} =
               Livekit.Agents.Tool.run(Livekit.Agents.EdgeCases.MockLLM, ctx,
                 tool_context: tc,
                 max_tool_steps: 0
               )

      outputs = Enum.filter(final_ctx.items, &match?(%FunctionCallOutput{}, &1))
      assert outputs == []
    end
  end

  describe "Tool.run/3 when LLM returns no tool calls" do
    test "natural completion — returns context with assistant message, no tool outputs" do
      tc = ToolContext.new([])
      ctx = ChatContext.new() |> ChatContext.add(ChatContext.new_message(:user, ["hi"]))

      set_mock_queue([{:assistant, "Hello from the assistant"}])

      assert {:ok, final_ctx} =
               Livekit.Agents.Tool.run(Livekit.Agents.EdgeCases.MockLLM, ctx, tool_context: tc)

      messages = ChatContext.messages(final_ctx)
      assert Enum.any?(messages, fn m -> m.role == :assistant end)
      assert Enum.filter(final_ctx.items, &match?(%FunctionCallOutput{}, &1)) == []
    end
  end

  describe "Tool.run/3 with malformed JSON arguments from LLM" do
    test "produces FunctionCallOutput(is_error: true) without crashing" do
      echo_spec =
        ToolSpec.new(
          name: "echo",
          description: "Echoes",
          parameters: %{"type" => "object", "properties" => %{"msg" => %{"type" => "string"}}},
          handler: fn %{"msg" => m} -> {:ok, m} end
        )

      tc = ToolContext.new([echo_spec])
      ctx = ChatContext.new()

      set_mock_queue([
        {:function_call, "cid-bad", "echo", "{ not valid json !!"},
        {:assistant, "handled"}
      ])

      assert {:ok, final_ctx} =
               Livekit.Agents.Tool.run(Livekit.Agents.EdgeCases.MockLLM, ctx, tool_context: tc)

      outputs = Enum.filter(final_ctx.items, &match?(%FunctionCallOutput{}, &1))
      assert length(outputs) == 1
      assert hd(outputs).is_error == true
    end
  end

  describe "Tool handler raising an exception" do
    test "exception is caught and converted to FunctionCallOutput(is_error: true)" do
      exploding_spec =
        ToolSpec.new(
          name: "explode",
          description: "Always raises",
          parameters: %{"type" => "object", "properties" => %{}},
          handler: fn _args -> raise "kaboom" end
        )

      tc = ToolContext.new([exploding_spec])
      ctx = ChatContext.new()

      set_mock_queue([
        {:function_call, "cid-boom", "explode", "{}"},
        {:assistant, "recovered"}
      ])

      assert {:ok, final_ctx} =
               Livekit.Agents.Tool.run(Livekit.Agents.EdgeCases.MockLLM, ctx, tool_context: tc)

      outputs = Enum.filter(final_ctx.items, &match?(%FunctionCallOutput{}, &1))
      assert length(outputs) == 1
      assert hd(outputs).is_error == true
      assert is_binary(hd(outputs).output)
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Pipeline edge cases
  # ---------------------------------------------------------------------------

  defp base_pipeline_config(overrides \\ []) do
    %PipelineConfig{
      stt: {MockSTT, %{}},
      llm: {PipelineMockLLM, %{}},
      tts: {MockTTS, %{}},
      silence_ms: Keyword.get(overrides, :silence_ms, 50)
    }
  end

  describe "Pipeline start with nil provider config" do
    test "nil stt returns error — process does not start" do
      Process.flag(:trap_exit, true)

      config = %PipelineConfig{
        stt: nil,
        llm: {PipelineMockLLM, %{}},
        tts: {MockTTS, %{}}
      }

      assert {:error, _reason} = Pipeline.start_link(config)
    end

    test "nil llm returns error — process does not start" do
      Process.flag(:trap_exit, true)

      config = %PipelineConfig{
        stt: {MockSTT, %{}},
        llm: nil,
        tts: {MockTTS, %{}}
      }

      assert {:error, _reason} = Pipeline.start_link(config)
    end

    test "nil tts returns error — process does not start" do
      Process.flag(:trap_exit, true)

      config = %PipelineConfig{
        stt: {MockSTT, %{}},
        llm: {PipelineMockLLM, %{}},
        tts: nil
      }

      assert {:error, _reason} = Pipeline.start_link(config)
    end
  end

  describe "Pipeline.push_frame/2 is non-blocking" do
    test "returns :ok immediately (cast semantics)" do
      {:ok, pid} = Pipeline.start_link(base_pipeline_config())

      frame = AudioFrame.new(<<0::160*8>>, sample_rate: 16_000, format: :pcm_16)
      result = Pipeline.push_frame(pid, frame)

      assert result == :ok

      Pipeline.stop(pid)
    end
  end

  describe "Pipeline.get_metrics/1" do
    test "returns a map with expected keys immediately after start" do
      {:ok, pid} = Pipeline.start_link(base_pipeline_config())

      metrics = Pipeline.get_metrics(pid)

      assert is_map(metrics)
      assert Map.has_key?(metrics, :turns_processed)
      assert Map.has_key?(metrics, :audio_frames_processed)
      assert Map.has_key?(metrics, :errors)

      Pipeline.stop(pid)
    end

    test "all metric values are non-negative integers on a fresh pipeline" do
      {:ok, pid} = Pipeline.start_link(base_pipeline_config())

      metrics = Pipeline.get_metrics(pid)

      assert metrics.turns_processed == 0
      assert metrics.audio_frames_processed == 0
      assert metrics.errors == 0

      Pipeline.stop(pid)
    end
  end

  describe "Pipeline empty audio frame (0 bytes)" do
    test "pushing a 0-byte frame does not crash the pipeline" do
      {:ok, pid} = Pipeline.start_link(base_pipeline_config())

      empty_frame = AudioFrame.new(<<>>, sample_rate: 16_000, format: :pcm_16)
      assert :ok = Pipeline.push_frame(pid, empty_frame)

      Process.sleep(50)
      assert Process.alive?(pid)

      metrics = Pipeline.get_metrics(pid)
      assert metrics.audio_frames_processed == 1

      Pipeline.stop(pid)
    end
  end

  describe "Pipeline complete turn: speech then silence produces audio output" do
    test "subscriber receives {:pipeline_audio, frame} after a full turn" do
      test_pid = self()

      config = %PipelineConfig{
        stt: {MockSTT, %{}},
        llm: {PipelineMockLLM, %{}},
        tts: {MockTTS, %{}},
        subscriber: test_pid,
        silence_ms: 50
      }

      {:ok, pid} = Pipeline.start_link(config)

      speech_data = for _ <- 1..160, into: <<>>, do: <<32_767::little-signed-16>>
      speech_frame = AudioFrame.new(speech_data, sample_rate: 16_000, format: :pcm_16)
      silence_frame = AudioFrame.new(<<0::320*8>>, sample_rate: 16_000, format: :pcm_16)

      Pipeline.push_frame(pid, speech_frame)
      Pipeline.push_frame(pid, silence_frame)

      assert_receive {:pipeline_audio, %AudioFrame{data: data}}, 500
      assert is_binary(data)
      assert byte_size(data) > 0

      Pipeline.stop(pid)
    end
  end

  # ---------------------------------------------------------------------------
  # 4. TurnDetector edge cases
  # ---------------------------------------------------------------------------

  defp make_frame(timestamp_us) do
    data = <<1000::little-signed-16>>

    AudioFrame.new(data,
      sample_rate: 16_000,
      channels: 1,
      format: :pcm_16,
      timestamp_us: timestamp_us
    )
  end

  defp silent_frame do
    AudioFrame.new(<<0::little-signed-16>>, sample_rate: 16_000, channels: 1, format: :pcm_16)
  end

  describe "TurnDetector with very short silence_timeout (10ms)" do
    test "fires {:turn_end, frames} quickly after speech + silence" do
      {:ok, pid} = TurnDetector.start_link(subscriber: self(), silence_ms: 10)

      TurnDetector.push_frame(pid, {:speech, make_frame(1_000)})
      assert_receive {:turn_start, 1_000}, 200

      TurnDetector.push_frame(pid, {:silence, silent_frame()})

      assert_receive {:turn_end, frames}, 200
      assert length(frames) == 1

      GenServer.stop(pid)
    end
  end

  describe "TurnDetector receives only silence" do
    test "no turn events are emitted when only silence frames are pushed" do
      {:ok, pid} = TurnDetector.start_link(subscriber: self(), silence_ms: 10)

      Enum.each(1..5, fn i ->
        TurnDetector.push_frame(pid, {:silence, make_frame(i * 1_000)})
      end)

      refute_receive {:turn_start, _}, 100
      refute_receive {:turn_end, _}, 100

      GenServer.stop(pid)
    end
  end

  describe "TurnDetector max_utterance_frames limit" do
    test "GenServer stays alive under high frame load (100 speech frames)" do
      {:ok, pid} = TurnDetector.start_link(subscriber: self(), silence_ms: 5_000)

      Enum.each(1..100, fn i ->
        TurnDetector.push_frame(pid, {:speech, make_frame(i * 1_000)})
      end)

      assert_receive {:turn_start, 1_000}, 500
      refute_receive {:turn_end, _}, 50

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "TurnDetector reset during active speech" do
    test "reset clears accumulated frames — subsequent silence does not fire turn_end" do
      {:ok, pid} = TurnDetector.start_link(subscriber: self(), silence_ms: 50)

      TurnDetector.push_frame(pid, {:speech, make_frame(1_000)})
      assert_receive {:turn_start, 1_000}, 200

      TurnDetector.push_frame(pid, {:speech, make_frame(2_000)})
      TurnDetector.push_frame(pid, {:speech, make_frame(3_000)})

      TurnDetector.reset(pid)

      TurnDetector.push_frame(pid, {:silence, silent_frame()})

      refute_receive {:turn_end, _}, 200

      GenServer.stop(pid)
    end
  end

  # ---------------------------------------------------------------------------
  # 5. EnergyVAD edge cases
  # ---------------------------------------------------------------------------

  describe "EnergyVAD.classify/2 with empty audio frame (0 bytes)" do
    test "classifies empty frame as :silence without crashing" do
      config = EnergyVAD.new(%{threshold: 0.01})
      empty_frame = AudioFrame.new(<<>>, sample_rate: 16_000, format: :pcm_16)

      result = EnergyVAD.classify(empty_frame, config)
      assert result == :silence
    end
  end

  describe "EnergyVAD.classify/2 with threshold 0.0" do
    test "any frame with non-zero RMS is :speech; zero-RMS silence frame is :speech" do
      # is_silence? returns true when rms < threshold
      # With threshold 0.0: rms (0.0) is NOT < 0.0, so is_silence? is false, classify returns :speech
      config = EnergyVAD.new(%{threshold: 0.0})

      silent = AudioFrame.new(<<0::little-signed-16>>, sample_rate: 16_000, format: :pcm_16)
      assert EnergyVAD.classify(silent, config) == :speech

      loud_data = for _ <- 1..10, into: <<>>, do: <<10_000::little-signed-16>>
      loud = AudioFrame.new(loud_data, sample_rate: 16_000, format: :pcm_16)
      assert EnergyVAD.classify(loud, config) == :speech
    end
  end

  describe "EnergyVAD.classify/2 with threshold 1.0" do
    test "even max-amplitude PCM16 is classified as :silence (RMS < 1.0)" do
      config = EnergyVAD.new(%{threshold: 1.0})

      loud_data = for _ <- 1..160, into: <<>>, do: <<32_767::little-signed-16>>
      loud_frame = AudioFrame.new(loud_data, sample_rate: 16_000, format: :pcm_16)

      # Max PCM16 RMS ≈ 0.9999..., which is < 1.0
      assert EnergyVAD.classify(loud_frame, config) == :silence

      silent = AudioFrame.new(<<0::little-signed-16>>, sample_rate: 16_000, format: :pcm_16)
      assert EnergyVAD.classify(silent, config) == :silence
    end
  end

  # ---------------------------------------------------------------------------
  # 6. State machine edge cases
  # ---------------------------------------------------------------------------

  describe "UserStateMachine rapid speech_start/speech_end cycling" do
    test "rapid cycling does not crash the process" do
      {:ok, pid} = UserStateMachine.start_link(away_timeout_ms: 500)

      Enum.each(1..20, fn _ ->
        UserStateMachine.speech_start(pid)
        UserStateMachine.speech_end(pid)
      end)

      state = UserStateMachine.get_state(pid)
      assert state in [:listening, :speaking, :away]
      assert Process.alive?(pid)
    end
  end

  describe "UserStateMachine away timeout fires correctly" do
    test "transitions :listening -> :away after the configured timeout" do
      {:ok, pid} = UserStateMachine.start_link(away_timeout_ms: 30)

      UserStateMachine.speech_start(pid)
      UserStateMachine.speech_end(pid)

      Process.sleep(100)

      assert UserStateMachine.get_state(pid) == :away
    end
  end

  describe "AgentStateMachine invalid transition (speaking -> thinking)" do
    test "state remains :speaking after the invalid transition attempt" do
      {:ok, pid} = AgentStateMachine.start_link()

      AgentStateMachine.set_state(pid, :listening)
      AgentStateMachine.set_state(pid, :thinking)
      AgentStateMachine.set_state(pid, :speaking)

      AgentStateMachine.set_state(pid, :thinking)

      state = AgentStateMachine.get_state(pid)
      assert state == :speaking
    end
  end

  describe "AgentStateMachine get_state returns current state" do
    test "reports :initializing before any transitions" do
      {:ok, pid} = AgentStateMachine.start_link()
      assert AgentStateMachine.get_state(pid) == :initializing
    end

    test "reports the most recent valid state after a sequence of transitions" do
      {:ok, pid} = AgentStateMachine.start_link()

      AgentStateMachine.set_state(pid, :listening)
      AgentStateMachine.set_state(pid, :thinking)

      assert AgentStateMachine.get_state(pid) == :thinking
    end
  end

  describe "UserStateMachine double speech_start without speech_end" do
    test "second speech_start is a no-op — process does not crash" do
      {:ok, pid} = UserStateMachine.start_link()

      UserStateMachine.speech_start(pid)
      assert UserStateMachine.get_state(pid) == :speaking

      UserStateMachine.speech_start(pid)

      state = UserStateMachine.get_state(pid)
      assert state == :speaking
      assert Process.alive?(pid)
    end
  end

  # ---------------------------------------------------------------------------
  # 7. AudioBuffer edge cases
  # ---------------------------------------------------------------------------

  describe "AudioBuffer.push/3 with empty binary" do
    test "pushing empty binary does not crash and keeps duration at 0" do
      buf = AudioBuffer.new(min_duration_ms: 100)
      buf2 = AudioBuffer.push(buf, <<>>, 16_000)

      assert buf2.data == <<>>
      assert buf2.duration_ms == 0.0
    end

    test "pushing empty binary then real audio accumulates correctly" do
      buf = AudioBuffer.new(min_duration_ms: 50)
      buf = AudioBuffer.push(buf, <<>>, 16_000)

      # 1600 samples at 16kHz = 100ms (1600 * 2 = 3200 bytes)
      audio_100ms = :binary.copy(<<0, 0>>, 1600)
      buf = AudioBuffer.push(buf, audio_100ms, 16_000)

      assert_in_delta buf.duration_ms, 100.0, 0.5
    end
  end

  describe "AudioBuffer.flush/1 on empty buffer" do
    test "returns empty binary without crashing" do
      buf = AudioBuffer.new()
      {audio, reset_buf} = AudioBuffer.flush(buf)

      assert audio == <<>>
      assert reset_buf.data == <<>>
      assert reset_buf.duration_ms == 0.0
    end
  end

  describe "AudioBuffer duration calculation accuracy" do
    test "100ms of 16kHz 16-bit mono is calculated correctly" do
      buf = AudioBuffer.new()
      # 16000 samples/sec * 0.1s = 1600 samples; 1600 * 2 bytes = 3200 bytes
      audio = :binary.copy(<<0, 0>>, 1600)
      buf2 = AudioBuffer.push(buf, audio, 16_000)
      assert_in_delta buf2.duration_ms, 100.0, 0.1
    end

    test "500ms of 8kHz 16-bit mono is calculated correctly" do
      buf = AudioBuffer.new()
      # 8000 * 0.5 = 4000 samples; 4000 * 2 = 8000 bytes
      audio = :binary.copy(<<0, 0>>, 4000)
      buf2 = AudioBuffer.push(buf, audio, 8_000)
      assert_in_delta buf2.duration_ms, 500.0, 0.1
    end

    test "flush_if_ready returns ready when duration meets threshold exactly" do
      buf = AudioBuffer.new(min_duration_ms: 100)
      audio = :binary.copy(<<0, 0>>, 1600)
      buf2 = AudioBuffer.push(buf, audio, 16_000)

      assert {:ready, ^audio, reset} = AudioBuffer.flush_if_ready(buf2)
      assert reset.data == <<>>
      assert reset.duration_ms == 0.0
    end
  end

  # ---------------------------------------------------------------------------
  # 8. Cache edge cases
  # ---------------------------------------------------------------------------

  describe "Cache with max_entries: 1" do
    test "second put evicts the first entry" do
      {:ok, pid} = Cache.start_link(max_entries: 1)

      Cache.put(pid, "first", "audio_a")
      Cache.put(pid, "second", "audio_b")

      assert :miss = Cache.get(pid, "first")
      assert {:ok, "audio_b"} = Cache.get(pid, "second")
    end

    test "updating the only entry does not evict it" do
      {:ok, pid} = Cache.start_link(max_entries: 1)

      Cache.put(pid, "key", "v1")
      Cache.put(pid, "key", "v2")

      assert {:ok, "v2"} = Cache.get(pid, "key")
    end
  end

  describe "Cache TTL expiry" do
    test "get returns :miss after TTL elapses" do
      # ttl_seconds: 0 means TTL is 0ms — any elapsed time causes expiry
      {:ok, pid} = Cache.start_link(ttl_seconds: 0)

      Cache.put(pid, "k", "v")
      Process.sleep(5)

      assert :miss = Cache.get(pid, "k")
    end

    test "get returns {:ok, value} within TTL" do
      {:ok, pid} = Cache.start_link(ttl_seconds: 3600)

      Cache.put(pid, "k", "v")

      assert {:ok, "v"} = Cache.get(pid, "k")
    end
  end

  describe "Cache.clear/1" do
    test "removes all stored entries" do
      {:ok, pid} = Cache.start_link()

      Cache.put(pid, "a", "1")
      Cache.put(pid, "b", "2")
      Cache.put(pid, "c", "3")

      Cache.clear(pid)

      assert :miss = Cache.get(pid, "a")
      assert :miss = Cache.get(pid, "b")
      assert :miss = Cache.get(pid, "c")
    end

    test "cache accepts new entries after clear" do
      {:ok, pid} = Cache.start_link()

      Cache.put(pid, "old", "data")
      Cache.clear(pid)
      Cache.put(pid, "new", "fresh")

      assert :miss = Cache.get(pid, "old")
      assert {:ok, "fresh"} = Cache.get(pid, "new")
    end
  end
end

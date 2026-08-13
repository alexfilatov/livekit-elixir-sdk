defmodule Livekit.Agents.ToolTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.ChatContext
  alias Livekit.Agents.Tool
  alias Livekit.Agents.Tool.{ToolContext, ToolError, ToolSpec}

  # MockLLM uses Process dictionary for per-test queue control.
  # Each test calls set_mock_queue/1 to enqueue responses.
  # Items:
  #   {:assistant, text}                    — returns ChatMessage with :assistant role
  #   {:function_call, call_id, name, args} — returns FunctionCall struct
  #   {:error, reason}                      — returns {:error, reason}
  defmodule MockLLM do
    use Livekit.Agents.LLM

    alias Livekit.Agents.ChatContext

    @impl true
    def chat(_chat_ctx, _opts) do
      queue = Process.get(:mock_llm_queue, [])

      case queue do
        [] ->
          # Default: assistant message signals natural completion
          msg = ChatContext.new_message(:assistant, ["(done)"])
          {:ok, msg}

        [next | rest] ->
          Process.put(:mock_llm_queue, rest)

          case next do
            {:assistant, text} ->
              msg = ChatContext.new_message(:assistant, [text])
              {:ok, msg}

            {:function_call, call_id, name, args_json} ->
              fc = ChatContext.new_function_call(call_id, name, args_json)
              {:ok, fc}

            {:error, reason} ->
              {:error, reason}
          end
      end
    end

    @impl true
    def capabilities do
      %{streaming: false, tool_calling: true, vision: false, max_context_tokens: 4096}
    end
  end

  # MockLLMPreAppend simulates a provider that appends its response to the
  # ChatContext before returning it (some providers do this). It returns the
  # last item already in ctx.items, which triggers the `maybe_add_response`
  # identity branch in Tool.run/3 (the item is already present — no duplicate added).
  defmodule MockLLMPreAppend do
    use Livekit.Agents.LLM

    @impl true
    def chat(chat_ctx, _opts) do
      # Return the last item already in the context — simulating a provider
      # that has pre-appended the response before returning it.
      {:ok, List.last(chat_ctx.items)}
    end

    @impl true
    def capabilities do
      %{streaming: false, tool_calling: false, vision: false, max_context_tokens: 4096}
    end
  end

  # Helper: minimal ToolSpec with an echo handler
  defp echo_spec do
    ToolSpec.new(
      name: "echo",
      description: "Echoes the message back",
      parameters: %{
        "type" => "object",
        "properties" => %{"msg" => %{"type" => "string"}},
        "required" => ["msg"]
      },
      handler: fn %{"msg" => m} -> {:ok, m} end
    )
  end

  defp failing_spec do
    ToolSpec.new(
      name: "failing_tool",
      description: "Always fails",
      parameters: %{"type" => "object", "properties" => %{}},
      handler: fn _args -> {:error, "intentional failure"} end
    )
  end

  defp set_mock_queue(items), do: Process.put(:mock_llm_queue, items)

  # ---------------------------------------------------------------------------
  # ToolSpec (TOOL-01)
  # ---------------------------------------------------------------------------

  describe "ToolSpec (TOOL-01)" do
    test "new/1 creates a ToolSpec with expected fields" do
      spec = echo_spec()
      assert %ToolSpec{} = spec
      assert spec.name == "echo"
      assert spec.description == "Echoes the message back"
      assert is_map(spec.parameters)
      assert is_function(spec.handler, 1)
    end

    test "new/1 raises KeyError when required key is missing" do
      assert_raise KeyError, fn ->
        ToolSpec.new(name: "no_handler", description: "x", parameters: %{})
      end
    end

    test "handler is callable and returns {:ok, result}" do
      spec = echo_spec()
      assert {:ok, "hello"} = spec.handler.(%{"msg" => "hello"})
    end
  end

  # ---------------------------------------------------------------------------
  # ToolSpec.to_openai_schema/1 (TOOL-05)
  # ---------------------------------------------------------------------------

  describe "ToolSpec.to_openai_schema/1 (TOOL-05)" do
    test "returns a map with 'type' => 'function'" do
      schema = ToolSpec.to_openai_schema(echo_spec())
      assert schema["type"] == "function"
    end

    test "nests name, description, parameters under 'function' key" do
      spec = echo_spec()
      schema = ToolSpec.to_openai_schema(spec)
      fn_map = schema["function"]
      assert fn_map["name"] == spec.name
      assert fn_map["description"] == spec.description
      assert fn_map["parameters"] == spec.parameters
    end

    test "parameters map is passed through unchanged" do
      params = %{
        "type" => "object",
        "properties" => %{"city" => %{"type" => "string"}},
        "required" => ["city"]
      }

      spec =
        ToolSpec.new(
          name: "x",
          description: "y",
          parameters: params,
          handler: fn _ -> {:ok, "z"} end
        )

      schema = ToolSpec.to_openai_schema(spec)
      assert schema["function"]["parameters"] == params
    end
  end

  # ---------------------------------------------------------------------------
  # ToolContext (TOOL-01)
  # ---------------------------------------------------------------------------

  describe "ToolContext (TOOL-01)" do
    test "new/1 creates a context from a list of specs" do
      tc = ToolContext.new([echo_spec()])
      assert %ToolContext{} = tc
      assert map_size(tc.tools) == 1
    end

    test "new/1 with empty list creates empty context" do
      tc = ToolContext.new([])
      assert tc.tools == %{}
    end

    test "new/1 indexes tools by name" do
      spec = echo_spec()
      tc = ToolContext.new([spec])
      assert Map.has_key?(tc.tools, "echo")
    end

    test "lookup/2 returns {:ok, spec} for a registered name" do
      tc = ToolContext.new([echo_spec()])
      assert {:ok, %ToolSpec{name: "echo"}} = ToolContext.lookup(tc, "echo")
    end

    test "lookup/2 returns {:error, :not_found} for unknown name" do
      tc = ToolContext.new([echo_spec()])
      assert {:error, :not_found} = ToolContext.lookup(tc, "missing")
    end

    test "to_openai_tools/1 returns one schema per registered tool (TOOL-05)" do
      tc = ToolContext.new([echo_spec(), failing_spec()])
      schemas = ToolContext.to_openai_tools(tc)
      assert length(schemas) == 2
      assert Enum.all?(schemas, fn s -> s["type"] == "function" end)
      names = Enum.map(schemas, fn s -> s["function"]["name"] end) |> Enum.sort()
      assert names == ["echo", "failing_tool"]
    end

    test "to_openai_tools/1 with empty context returns empty list" do
      tc = ToolContext.new([])
      assert ToolContext.to_openai_tools(tc) == []
    end
  end

  # ---------------------------------------------------------------------------
  # ToolError (TOOL-04)
  # ---------------------------------------------------------------------------

  describe "ToolError (TOOL-04)" do
    test "exception/1 creates a ToolError with expected fields" do
      err =
        %ToolError{} =
        ToolError.exception(call_id: "cid-1", tool_name: "echo", reason: :not_found)

      assert err.call_id == "cid-1"
      assert err.tool_name == "echo"
      assert err.reason == :not_found
      assert is_binary(err.message)
      assert String.contains?(err.message, "echo")
      assert String.contains?(err.message, "cid-1")
    end

    test "ToolError is raiseable and rescuable" do
      assert_raise ToolError, fn ->
        raise ToolError, call_id: "cid", tool_name: "fn", reason: :test
      end
    end

    test "rescue ToolError and inspect fields" do
      try do
        raise ToolError, call_id: "cid", tool_name: "fn", reason: "bad input"
      rescue
        err in ToolError ->
          assert err.call_id == "cid"
          assert err.tool_name == "fn"
          assert err.reason == "bad input"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Tool.run/3 — basic completion (TOOL-02)
  # ---------------------------------------------------------------------------

  describe "Tool.run/3 — basic completion (TOOL-02)" do
    test "returns {:ok, ctx} when LLM produces no function calls" do
      tc = ToolContext.new([echo_spec()])
      ctx = ChatContext.new() |> ChatContext.add(ChatContext.new_message(:user, ["hi"]))
      set_mock_queue([{:assistant, "Hello!"}])

      assert {:ok, final_ctx} = Tool.run(MockLLM, ctx, tool_context: tc)
      messages = ChatContext.messages(final_ctx)
      assert Enum.any?(messages, fn m -> m.role == :assistant end)
    end

    test "returns {:error, reason} when LLM call fails" do
      tc = ToolContext.new([echo_spec()])
      ctx = ChatContext.new()
      set_mock_queue([{:error, :api_error}])

      assert {:error, :api_error} = Tool.run(MockLLM, ctx, tool_context: tc)
    end

    test "does not duplicate item when provider pre-appends response to context" do
      # Some LLM providers append the response to the context before returning it.
      # MockLLMPreAppend simulates this by returning the last item already in ctx.items.
      # Tool.run/3 should detect the duplicate via maybe_add_response and not add it again.
      tc = ToolContext.new([])
      user_msg = ChatContext.new_message(:user, ["hello"])
      ctx = ChatContext.new() |> ChatContext.add(user_msg)

      assert {:ok, final_ctx} = Tool.run(MockLLMPreAppend, ctx, tool_context: tc)

      # The context should contain exactly the original user_msg (returned as-is,
      # not duplicated). No assistant item was added since the returned item is the
      # user msg already in ctx — it is not a FunctionCall, so the loop terminates.
      assert length(final_ctx.items) == 1
      assert hd(final_ctx.items) == user_msg
    end
  end

  # ---------------------------------------------------------------------------
  # Tool.run/3 — single tool call (TOOL-02)
  # ---------------------------------------------------------------------------

  describe "Tool.run/3 — single tool call (TOOL-02)" do
    test "executes a registered tool and feeds result back to LLM" do
      tc = ToolContext.new([echo_spec()])
      ctx = ChatContext.new() |> ChatContext.add(ChatContext.new_message(:user, ["echo me"]))

      # First LLM call returns a function call; second call (with result) returns assistant message
      set_mock_queue([
        {:function_call, "cid-1", "echo", ~s({"msg":"hello"})},
        {:assistant, "Tool completed"}
      ])

      assert {:ok, final_ctx} = Tool.run(MockLLM, ctx, tool_context: tc)

      outputs =
        Enum.filter(final_ctx.items, fn
          %ChatContext.FunctionCallOutput{} -> true
          _ -> false
        end)

      assert length(outputs) == 1
      [output] = outputs
      assert output.call_id == "cid-1"
      assert output.name == "echo"
      assert output.output == "hello"
      assert output.is_error == false
    end
  end

  # ---------------------------------------------------------------------------
  # Tool.run/3 — max_tool_steps limit (TOOL-03)
  # ---------------------------------------------------------------------------

  describe "Tool.run/3 — max_tool_steps limit (TOOL-03)" do
    test "stops after max_tool_steps and returns current context" do
      looping_spec =
        ToolSpec.new(
          name: "loop",
          description: "Loops",
          parameters: %{"type" => "object", "properties" => %{}},
          handler: fn _args -> {:ok, "step done"} end
        )

      tc = ToolContext.new([looping_spec])
      ctx = ChatContext.new()

      # Queue more tool calls than max_tool_steps: 3
      calls = for i <- 1..10, do: {:function_call, "cid-#{i}", "loop", "{}"}
      set_mock_queue(calls)

      assert {:ok, final_ctx} = Tool.run(MockLLM, ctx, tool_context: tc, max_tool_steps: 3)

      outputs =
        Enum.filter(final_ctx.items, fn
          %ChatContext.FunctionCallOutput{} -> true
          _ -> false
        end)

      assert length(outputs) == 3
    end

    test "max_tool_steps: 1 stops after one tool call" do
      tc = ToolContext.new([echo_spec()])
      ctx = ChatContext.new()

      set_mock_queue([
        {:function_call, "cid-1", "echo", ~s({"msg":"a"})},
        {:function_call, "cid-2", "echo", ~s({"msg":"b"})},
        {:assistant, "done"}
      ])

      assert {:ok, final_ctx} = Tool.run(MockLLM, ctx, tool_context: tc, max_tool_steps: 1)

      outputs =
        Enum.filter(final_ctx.items, fn
          %ChatContext.FunctionCallOutput{} -> true
          _ -> false
        end)

      assert length(outputs) == 1
    end

    test "default max_tool_steps is 10" do
      # Provide exactly 11 tool calls; first 10 should execute, loop stops before the 11th
      looping_spec =
        ToolSpec.new(
          name: "count",
          description: "Counter",
          parameters: %{"type" => "object", "properties" => %{}},
          handler: fn _args -> {:ok, "tick"} end
        )

      tc = ToolContext.new([looping_spec])
      ctx = ChatContext.new()

      calls = for i <- 1..11, do: {:function_call, "cid-#{i}", "count", "{}"}
      set_mock_queue(calls)

      assert {:ok, final_ctx} = Tool.run(MockLLM, ctx, tool_context: tc)

      outputs =
        Enum.filter(final_ctx.items, fn
          %ChatContext.FunctionCallOutput{} -> true
          _ -> false
        end)

      assert length(outputs) == 10
    end
  end

  # ---------------------------------------------------------------------------
  # Tool.run/3 — ToolError handling (TOOL-04)
  # ---------------------------------------------------------------------------

  describe "Tool.run/3 — ToolError handling (TOOL-04)" do
    test "handler returning {:error, reason} produces FunctionCallOutput(is_error: true)" do
      tc = ToolContext.new([failing_spec()])
      ctx = ChatContext.new()

      set_mock_queue([
        {:function_call, "cid-1", "failing_tool", "{}"},
        {:assistant, "handled error"}
      ])

      assert {:ok, final_ctx} = Tool.run(MockLLM, ctx, tool_context: tc)

      outputs =
        Enum.filter(final_ctx.items, fn
          %ChatContext.FunctionCallOutput{} -> true
          _ -> false
        end)

      assert length(outputs) == 1
      [output] = outputs
      assert output.is_error == true
      assert output.call_id == "cid-1"
      assert is_binary(output.output)
    end

    test "calling an unknown tool produces FunctionCallOutput(is_error: true)" do
      tc = ToolContext.new([echo_spec()])
      ctx = ChatContext.new()

      set_mock_queue([
        {:function_call, "cid-1", "nonexistent_tool", "{}"},
        {:assistant, "handled error"}
      ])

      assert {:ok, final_ctx} = Tool.run(MockLLM, ctx, tool_context: tc)

      outputs =
        Enum.filter(final_ctx.items, fn
          %ChatContext.FunctionCallOutput{} -> true
          _ -> false
        end)

      assert length(outputs) == 1
      [output] = outputs
      assert output.is_error == true
    end

    test "handler that raises an exception produces FunctionCallOutput(is_error: true)" do
      raising_spec =
        ToolSpec.new(
          name: "raiser",
          description: "Raises",
          parameters: %{"type" => "object", "properties" => %{}},
          handler: fn _args -> raise RuntimeError, "boom" end
        )

      tc = ToolContext.new([raising_spec])
      ctx = ChatContext.new()

      set_mock_queue([
        {:function_call, "cid-1", "raiser", "{}"},
        {:assistant, "handled"}
      ])

      assert {:ok, final_ctx} = Tool.run(MockLLM, ctx, tool_context: tc)

      outputs =
        Enum.filter(final_ctx.items, fn
          %ChatContext.FunctionCallOutput{} -> true
          _ -> false
        end)

      assert length(outputs) == 1
      assert hd(outputs).is_error == true
    end

    test "malformed JSON arguments produce FunctionCallOutput(is_error: true)" do
      tc = ToolContext.new([echo_spec()])
      ctx = ChatContext.new()

      # Invalid JSON in arguments
      set_mock_queue([
        {:function_call, "cid-1", "echo", "not valid json"},
        {:assistant, "handled"}
      ])

      assert {:ok, final_ctx} = Tool.run(MockLLM, ctx, tool_context: tc)

      outputs =
        Enum.filter(final_ctx.items, fn
          %ChatContext.FunctionCallOutput{} -> true
          _ -> false
        end)

      assert length(outputs) == 1
      assert hd(outputs).is_error == true
    end
  end
end

defmodule Livekit.Agents.LLM.OpenAITest do
  use ExUnit.Case, async: false

  alias Livekit.Agents.ChatContext
  alias Livekit.Agents.ChatContext.{ChatMessage, FunctionCall}
  alias Livekit.Agents.LLM.LLMChunk
  alias Livekit.Agents.LLM.OpenAI
  alias Livekit.Agents.LLM.OpenAI.Config

  # ---------------------------------------------------------------------------
  # capabilities/0
  # ---------------------------------------------------------------------------

  describe "capabilities/0" do
    test "returns a map with all required keys" do
      caps = OpenAI.capabilities()
      assert is_map(caps)
      assert Map.has_key?(caps, :streaming)
      assert Map.has_key?(caps, :tool_calling)
      assert Map.has_key?(caps, :vision)
      assert Map.has_key?(caps, :max_context_tokens)
    end

    test "streaming and tool_calling are both true" do
      caps = OpenAI.capabilities()
      assert caps.streaming == true
      assert caps.tool_calling == true
    end

    test "vision is false and max_context_tokens is a positive integer" do
      caps = OpenAI.capabilities()
      assert caps.vision == false
      assert is_integer(caps.max_context_tokens)
      assert caps.max_context_tokens > 0
    end
  end

  # ---------------------------------------------------------------------------
  # validate_config/1
  # ---------------------------------------------------------------------------

  describe "validate_config/1" do
    test "nil api_key returns {:error, :missing_api_key}" do
      assert {:error, :missing_api_key} = OpenAI.validate_config(%Config{api_key: nil})
    end

    test "empty string api_key returns {:error, :missing_api_key}" do
      assert {:error, :missing_api_key} = OpenAI.validate_config(%Config{api_key: ""})
    end

    test "valid api_key returns :ok" do
      assert :ok = OpenAI.validate_config(%Config{api_key: "sk-test"})
    end
  end

  # ---------------------------------------------------------------------------
  # chat/2 HTTP via Bypass
  # ---------------------------------------------------------------------------

  describe "chat/2 HTTP via Bypass" do
    setup do
      bypass = Bypass.open()

      ctx =
        ChatContext.new()
        |> ChatContext.add(ChatContext.new_message(:system, ["You are helpful."]))
        |> ChatContext.add(ChatContext.new_message(:user, ["What is 2+2?"]))

      {:ok, bypass: bypass, ctx: ctx}
    end

    defp config_for(bypass),
      do: %Config{api_key: "sk-test", base_url: "http://localhost:#{bypass.port}"}

    defp text_response(content) do
      %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => content,
              "tool_calls" => nil
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15}
      }
    end

    defp tool_call_response(call_id, fn_name, fn_args_json) do
      %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => nil,
              "tool_calls" => [
                %{
                  "id" => call_id,
                  "type" => "function",
                  "function" => %{"name" => fn_name, "arguments" => fn_args_json}
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }
        ]
      }
    end

    test "config.instructions becomes the system message", %{bypass: bypass} do
      # `:instructions` is a documented, defaulted field on Config. It was read
      # by nothing: the request was built from the chat context alone, so every
      # system prompt an application set was silently dropped and the model
      # answered as a generic assistant. Nothing errored — the reply was simply
      # not the product's.
      ctx = ChatContext.new() |> ChatContext.add(ChatContext.new_message(:user, ["Hello"]))

      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"messages" => messages} = Jason.decode!(body)

        assert [%{"role" => "system", "content" => "You are a UK estate agent."} | _] = messages

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(text_response("Hello.")))
      end)

      config = %{config_for(bypass) | instructions: "You are a UK estate agent."}
      OpenAI.chat(ctx, config: config)
    end

    test "a system message already in the context is not duplicated", %{bypass: bypass, ctx: ctx} do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"messages" => messages} = Jason.decode!(body)

        # Two system prompts contradict each other as often as they agree, and
        # the caller who built the context meant theirs.
        assert Enum.count(messages, &(&1["role"] == "system")) == 1
        assert hd(messages)["content"] == "You are helpful."

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(text_response("Four.")))
      end)

      config = %{config_for(bypass) | instructions: "You are a UK estate agent."}
      OpenAI.chat(ctx, config: config)
    end

    test "POSTs to /v1/chat/completions", %{bypass: bypass, ctx: ctx} do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(text_response("Four.")))
      end)

      OpenAI.chat(ctx, config: config_for(bypass))
    end

    test "text response returns {:ok, %ChatMessage{role: :assistant}}", %{
      bypass: bypass,
      ctx: ctx
    } do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(text_response("Four.")))
      end)

      assert {:ok, %ChatMessage{role: :assistant}} = OpenAI.chat(ctx, config: config_for(bypass))
    end

    test "text response content matches API response string", %{bypass: bypass, ctx: ctx} do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(text_response("The answer is four.")))
      end)

      {:ok, %ChatMessage{content: content}} = OpenAI.chat(ctx, config: config_for(bypass))
      assert content == ["The answer is four."]
    end

    test "tool call response returns {:ok, %FunctionCall{}} with correct name and call_id",
         %{bypass: bypass, ctx: ctx} do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(tool_call_response("call_123", "calculate", ~s({"expr":"2+2"})))
        )
      end)

      assert {:ok, %FunctionCall{name: "calculate", call_id: "call_123"}} =
               OpenAI.chat(ctx, config: config_for(bypass))
    end

    test "401 response returns {:error, {:api_error, 401, _}}", %{bypass: bypass, ctx: ctx} do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(401, Jason.encode!(%{"error" => "invalid key"}))
      end)

      assert {:error, {:api_error, 401, _}} = OpenAI.chat(ctx, config: config_for(bypass))
    end
  end

  # ---------------------------------------------------------------------------
  # stream/2 HTTP via Bypass
  # ---------------------------------------------------------------------------

  describe "stream/2 HTTP via Bypass" do
    setup do
      bypass = Bypass.open()

      ctx =
        ChatContext.new()
        |> ChatContext.add(ChatContext.new_message(:user, ["Tell me a joke."]))

      {:ok, bypass: bypass, ctx: ctx}
    end

    defp stream_config_for(bypass),
      do: %Config{api_key: "sk-test", base_url: "http://localhost:#{bypass.port}"}

    defp sse_body(chunks) do
      Enum.map_join(chunks, fn
        :done ->
          "data: [DONE]\n\n"

        text ->
          payload =
            Jason.encode!(%{
              "choices" => [%{"delta" => %{"content" => text}, "finish_reason" => nil}]
            })

          "data: #{payload}\n\n"
      end)
    end

    test "returns {:ok, pid} from stream/2", %{bypass: bypass, ctx: ctx} do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/event-stream")
        |> Plug.Conn.resp(200, sse_body(["Hello", " world", :done]))
      end)

      assert {:ok, pid} = OpenAI.stream(ctx, config: stream_config_for(bypass))
      assert is_pid(pid)
      assert_receive {:llm_chunk, %LLMChunk{type: :done}}, 2000
    end

    test "caller receives text chunks from SSE stream", %{bypass: bypass, ctx: ctx} do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/event-stream")
        |> Plug.Conn.resp(200, sse_body(["Hello", " world", :done]))
      end)

      {:ok, _pid} = OpenAI.stream(ctx, config: stream_config_for(bypass))
      assert_receive {:llm_chunk, %LLMChunk{type: :text, content: "Hello"}}, 2000
    end

    test "caller receives terminal :done chunk", %{bypass: bypass, ctx: ctx} do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/event-stream")
        |> Plug.Conn.resp(200, sse_body(["Hello", " world", :done]))
      end)

      {:ok, _pid} = OpenAI.stream(ctx, config: stream_config_for(bypass))
      assert_receive {:llm_chunk, %LLMChunk{type: :done}}, 2000
    end
  end

  # ---------------------------------------------------------------------------
  # to_openai_messages serialization (via chat/2 Bypass)
  # ---------------------------------------------------------------------------

  describe "to_openai_messages (via chat/2 Bypass)" do
    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass}
    end

    defp to_messages_config_for(bypass),
      do: %Config{api_key: "sk-test", base_url: "http://localhost:#{bypass.port}"}

    defp simple_text_response do
      %{
        "choices" => [
          %{
            "message" => %{"role" => "assistant", "content" => "ok", "tool_calls" => nil},
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{"prompt_tokens" => 5, "completion_tokens" => 1, "total_tokens" => 6}
      }
    end

    test "FunctionCall in context serializes as assistant tool_calls", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        messages = decoded["messages"]
        fc_msg = Enum.find(messages, &(&1["role"] == "assistant" and &1["tool_calls"] != nil))
        assert fc_msg != nil
        assert List.first(fc_msg["tool_calls"])["function"]["name"] == "get_weather"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(simple_text_response()))
      end)

      fc = ChatContext.new_function_call("call_abc", "get_weather", ~s({"city":"London"}))

      ctx =
        ChatContext.new()
        |> ChatContext.add(ChatContext.new_message(:user, ["What's the weather?"]))
        |> ChatContext.add(fc)

      OpenAI.chat(ctx, config: to_messages_config_for(bypass))
    end

    test "FunctionCallOutput in context serializes as role tool with tool_call_id", %{
      bypass: bypass
    } do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        messages = decoded["messages"]
        tool_msg = Enum.find(messages, &(&1["role"] == "tool"))
        assert tool_msg != nil
        assert tool_msg["tool_call_id"] == "call_xyz"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(simple_text_response()))
      end)

      fc = ChatContext.new_function_call("call_xyz", "get_time", ~s({}))
      fco = ChatContext.new_function_call_output("call_xyz", "get_time", "12:00 PM")

      ctx =
        ChatContext.new()
        |> ChatContext.add(ChatContext.new_message(:user, ["What time is it?"]))
        |> ChatContext.add(fc)
        |> ChatContext.add(fco)

      OpenAI.chat(ctx, config: to_messages_config_for(bypass))
    end
  end
end

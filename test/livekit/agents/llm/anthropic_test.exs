defmodule Livekit.Agents.LLM.AnthropicTest do
  use ExUnit.Case, async: false

  alias Livekit.Agents.ChatContext
  alias Livekit.Agents.ChatContext.{ChatMessage, FunctionCall}
  alias Livekit.Agents.LLM.Anthropic
  alias Livekit.Agents.LLM.Anthropic.Config
  alias Livekit.Agents.LLM.LLMChunk
  alias Livekit.Agents.Tool.{ToolContext, ToolSpec}

  # ---------------------------------------------------------------------------
  # capabilities/0
  # ---------------------------------------------------------------------------

  describe "capabilities/0" do
    test "returns a map with all required keys" do
      caps = Anthropic.capabilities()
      assert is_map(caps)
      assert Map.has_key?(caps, :streaming)
      assert Map.has_key?(caps, :tool_calling)
      assert Map.has_key?(caps, :vision)
      assert Map.has_key?(caps, :max_context_tokens)
    end

    test "streaming and tool_calling are both true" do
      caps = Anthropic.capabilities()
      assert caps.streaming == true
      assert caps.tool_calling == true
    end

    test "vision is true and max_context_tokens is a positive integer" do
      caps = Anthropic.capabilities()
      assert caps.vision == true
      assert is_integer(caps.max_context_tokens)
      assert caps.max_context_tokens > 0
    end
  end

  # ---------------------------------------------------------------------------
  # validate_config/1
  # ---------------------------------------------------------------------------

  describe "validate_config/1" do
    test "mock: true with nil api_key returns :ok" do
      assert :ok = Anthropic.validate_config(%Config{mock: true, api_key: nil})
    end

    test "mock: false with nil api_key returns {:error, :missing_api_key}" do
      assert {:error, :missing_api_key} =
               Anthropic.validate_config(%Config{mock: false, api_key: nil})
    end

    test "mock: false with empty string api_key returns {:error, :missing_api_key}" do
      assert {:error, :missing_api_key} =
               Anthropic.validate_config(%Config{mock: false, api_key: ""})
    end

    test "mock: false with valid api_key returns :ok" do
      assert :ok = Anthropic.validate_config(%Config{mock: false, api_key: "sk-ant-test"})
    end
  end

  # ---------------------------------------------------------------------------
  # chat/2 mock mode
  # ---------------------------------------------------------------------------

  describe "chat/2 mock mode" do
    setup do
      ctx = ChatContext.new() |> ChatContext.add(ChatContext.new_message(:user, ["Hello"]))
      config = %Config{mock: true}
      {:ok, ctx: ctx, config: config}
    end

    test "returns {:ok, result}", %{ctx: ctx, config: config} do
      assert {:ok, _result} = Anthropic.chat(ctx, config: config)
    end

    test "returned message has role :assistant", %{ctx: ctx, config: config} do
      {:ok, result} = Anthropic.chat(ctx, config: config)
      assert %ChatMessage{role: :assistant} = result
    end

    test "returned message content is a non-empty list", %{ctx: ctx, config: config} do
      {:ok, result} = Anthropic.chat(ctx, config: config)
      assert %ChatMessage{content: content} = result
      assert is_list(content)
      assert length(content) > 0
    end

    test "no api_key also triggers mock mode" do
      ctx = ChatContext.new() |> ChatContext.add(ChatContext.new_message(:user, ["Hi"]))
      config = %Config{api_key: nil, mock: false}
      assert {:ok, %ChatMessage{role: :assistant}} = Anthropic.chat(ctx, config: config)
    end
  end

  # ---------------------------------------------------------------------------
  # stream/2 mock mode
  # ---------------------------------------------------------------------------

  describe "stream/2 mock mode" do
    setup do
      ctx = ChatContext.new() |> ChatContext.add(ChatContext.new_message(:user, ["Hello"]))
      config = %Config{mock: true}
      {:ok, ctx: ctx, config: config}
    end

    test "returns {:ok, pid} where pid is a process", %{ctx: ctx, config: config} do
      assert {:ok, pid} = Anthropic.stream(ctx, config: config)
      assert is_pid(pid)
    end

    test "sends text chunk to caller", %{ctx: ctx, config: config} do
      {:ok, _pid} = Anthropic.stream(ctx, config: config)
      assert_receive {:llm_chunk, %LLMChunk{type: :text}}, 1000
    end

    test "sends done chunk to caller", %{ctx: ctx, config: config} do
      {:ok, _pid} = Anthropic.stream(ctx, config: config)
      assert_receive {:llm_chunk, %LLMChunk{type: :done}}, 1000
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
      do: %Config{
        api_key: "sk-ant-test",
        mock: false,
        base_url: "http://localhost:#{bypass.port}"
      }

    defp text_response(content) do
      %{
        "id" => "msg_01abc",
        "type" => "message",
        "role" => "assistant",
        "content" => [
          %{"type" => "text", "text" => content}
        ],
        "model" => "claude-sonnet-4-20250514",
        "stop_reason" => "end_turn",
        "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
      }
    end

    defp tool_use_response(call_id, fn_name, fn_input) do
      %{
        "id" => "msg_02def",
        "type" => "message",
        "role" => "assistant",
        "content" => [
          %{
            "type" => "tool_use",
            "id" => call_id,
            "name" => fn_name,
            "input" => fn_input
          }
        ],
        "model" => "claude-sonnet-4-20250514",
        "stop_reason" => "tool_use",
        "usage" => %{"input_tokens" => 15, "output_tokens" => 8}
      }
    end

    test "POSTs to /v1/messages", %{bypass: bypass, ctx: ctx} do
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(text_response("Four.")))
      end)

      Anthropic.chat(ctx, config: config_for(bypass))
    end

    test "sends x-api-key and anthropic-version headers", %{bypass: bypass, ctx: ctx} do
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        headers = Map.new(conn.req_headers)
        assert Map.has_key?(headers, "x-api-key")
        assert Map.has_key?(headers, "anthropic-version")

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(text_response("ok")))
      end)

      Anthropic.chat(ctx, config: config_for(bypass))
    end

    test "text response returns {:ok, %ChatMessage{role: :assistant}}", %{
      bypass: bypass,
      ctx: ctx
    } do
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(text_response("Four.")))
      end)

      assert {:ok, %ChatMessage{role: :assistant}} =
               Anthropic.chat(ctx, config: config_for(bypass))
    end

    test "text response content matches API response string", %{bypass: bypass, ctx: ctx} do
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(text_response("The answer is four.")))
      end)

      {:ok, %ChatMessage{content: content}} = Anthropic.chat(ctx, config: config_for(bypass))
      assert content == ["The answer is four."]
    end

    test "tool_use response returns {:ok, %FunctionCall{}} with correct name and call_id",
         %{bypass: bypass, ctx: ctx} do
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(tool_use_response("toolu_01abc", "calculate", %{"expr" => "2+2"}))
        )
      end)

      assert {:ok, %FunctionCall{name: "calculate", call_id: "toolu_01abc"}} =
               Anthropic.chat(ctx, config: config_for(bypass))
    end

    test "tool_use response FunctionCall.arguments is valid JSON", %{bypass: bypass, ctx: ctx} do
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(tool_use_response("toolu_02", "get_weather", %{"city" => "London"}))
        )
      end)

      {:ok, %FunctionCall{arguments: args_json}} =
        Anthropic.chat(ctx, config: config_for(bypass))

      assert {:ok, %{"city" => "London"}} = Jason.decode(args_json)
    end

    test "401 response returns {:error, {:api_error, 401, _}}", %{bypass: bypass, ctx: ctx} do
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(401, Jason.encode!(%{"error" => %{"message" => "invalid key"}}))
      end)

      assert {:error, {:api_error, 401, _}} = Anthropic.chat(ctx, config: config_for(bypass))
    end

    test "system message in context is extracted as system prompt", %{bypass: bypass, ctx: ctx} do
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        # System prompt must be at top level, not in messages array
        assert decoded["system"] == "You are helpful."
        # messages array must NOT contain a system role entry
        refute Enum.any?(decoded["messages"], &(&1["role"] == "system"))

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(text_response("ok")))
      end)

      Anthropic.chat(ctx, config: config_for(bypass))
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
      do: %Config{
        api_key: "sk-ant-test",
        mock: false,
        base_url: "http://localhost:#{bypass.port}"
      }

    defp sse_body(chunks) do
      Enum.map_join(chunks, fn
        :done ->
          event = ~s({"type":"message_stop"})
          "event: message_stop\ndata: #{event}\n\n"

        text ->
          payload =
            Jason.encode!(%{
              "type" => "content_block_delta",
              "index" => 0,
              "delta" => %{"type" => "text_delta", "text" => text}
            })

          "event: content_block_delta\ndata: #{payload}\n\n"
      end)
    end

    test "returns {:ok, pid} from stream/2", %{bypass: bypass, ctx: ctx} do
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/event-stream")
        |> Plug.Conn.resp(200, sse_body(["Hello", " world", :done]))
      end)

      assert {:ok, pid} = Anthropic.stream(ctx, config: stream_config_for(bypass))
      assert is_pid(pid)
      assert_receive {:llm_chunk, %LLMChunk{type: :done}}, 2000
    end

    test "caller receives text chunks from SSE stream", %{bypass: bypass, ctx: ctx} do
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/event-stream")
        |> Plug.Conn.resp(200, sse_body(["Hello", " world", :done]))
      end)

      {:ok, _pid} = Anthropic.stream(ctx, config: stream_config_for(bypass))
      assert_receive {:llm_chunk, %LLMChunk{type: :text, content: "Hello"}}, 2000
    end

    test "caller receives terminal :done chunk", %{bypass: bypass, ctx: ctx} do
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/event-stream")
        |> Plug.Conn.resp(200, sse_body(["Hello", " world", :done]))
      end)

      {:ok, _pid} = Anthropic.stream(ctx, config: stream_config_for(bypass))
      assert_receive {:llm_chunk, %LLMChunk{type: :done}}, 2000
    end
  end

  # ---------------------------------------------------------------------------
  # message conversion (via chat/2 Bypass)
  # ---------------------------------------------------------------------------

  describe "to_anthropic_messages (via chat/2 Bypass)" do
    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass}
    end

    defp to_messages_config_for(bypass),
      do: %Config{
        api_key: "sk-ant-test",
        mock: false,
        base_url: "http://localhost:#{bypass.port}"
      }

    defp simple_text_response do
      %{
        "id" => "msg_ok",
        "type" => "message",
        "role" => "assistant",
        "content" => [%{"type" => "text", "text" => "ok"}],
        "model" => "claude-sonnet-4-20250514",
        "stop_reason" => "end_turn",
        "usage" => %{"input_tokens" => 5, "output_tokens" => 1}
      }
    end

    test "FunctionCall in context serializes as assistant tool_use content block",
         %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        messages = decoded["messages"]

        assistant_msg =
          Enum.find(messages, fn m ->
            m["role"] == "assistant" and is_list(m["content"])
          end)

        assert assistant_msg != nil

        tool_use_block =
          Enum.find(assistant_msg["content"], &(&1["type"] == "tool_use"))

        assert tool_use_block != nil
        assert tool_use_block["name"] == "get_weather"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(simple_text_response()))
      end)

      fc = ChatContext.new_function_call("toolu_abc", "get_weather", ~s({"city":"London"}))

      ctx =
        ChatContext.new()
        |> ChatContext.add(ChatContext.new_message(:user, ["What's the weather?"]))
        |> ChatContext.add(fc)

      Anthropic.chat(ctx, config: to_messages_config_for(bypass))
    end

    test "FunctionCallOutput in context serializes as user message with tool_result block",
         %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        messages = decoded["messages"]

        user_msg_with_tool_result =
          Enum.find(messages, fn m ->
            m["role"] == "user" and is_list(m["content"]) and
              Enum.any?(m["content"], &(&1["type"] == "tool_result"))
          end)

        assert user_msg_with_tool_result != nil

        tool_result =
          Enum.find(user_msg_with_tool_result["content"], &(&1["type"] == "tool_result"))

        assert tool_result["tool_use_id"] == "toolu_xyz"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(simple_text_response()))
      end)

      fc = ChatContext.new_function_call("toolu_xyz", "get_time", ~s({}))
      fco = ChatContext.new_function_call_output("toolu_xyz", "get_time", "12:00 PM")

      ctx =
        ChatContext.new()
        |> ChatContext.add(ChatContext.new_message(:user, ["What time is it?"]))
        |> ChatContext.add(fc)
        |> ChatContext.add(fco)

      Anthropic.chat(ctx, config: to_messages_config_for(bypass))
    end

    test "tool_context is sent as tools array in request body", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert is_list(decoded["tools"])
        assert length(decoded["tools"]) == 1
        [tool] = decoded["tools"]
        assert tool["name"] == "get_weather"
        assert Map.has_key?(tool, "input_schema")

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(simple_text_response()))
      end)

      weather_tool =
        ToolSpec.new(
          name: "get_weather",
          description: "Returns current weather for a city",
          parameters: %{
            "type" => "object",
            "properties" => %{"city" => %{"type" => "string"}},
            "required" => ["city"]
          },
          handler: fn %{"city" => city} -> {:ok, "Sunny in #{city}"} end
        )

      tool_ctx = ToolContext.new([weather_tool])

      ctx =
        ChatContext.new()
        |> ChatContext.add(ChatContext.new_message(:user, ["What's the weather in Paris?"]))

      Anthropic.chat(ctx, config: to_messages_config_for(bypass), tool_context: tool_ctx)
    end
  end
end

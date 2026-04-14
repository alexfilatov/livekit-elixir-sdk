defmodule Livekit.Agents.LLM.Anthropic do
  @moduledoc """
  Anthropic Claude Large Language Model provider for LiveKit agents.

  Pure functional module implementing `@behaviour Livekit.Agents.LLM`. Sends HTTP
  POST requests to `/v1/messages` via Tesla, converts `ChatContext` items to the
  Anthropic messages wire format, and parses responses into `ChatMessage` or
  `FunctionCall` structs.

  The Anthropic Messages API differs from OpenAI in several important ways:

  - The system prompt is a top-level field, not a message in the `messages` array.
  - Tool use is signalled via `tool_use` content blocks (not `tool_calls`).
  - `max_tokens` is **required** by the Anthropic API.
  - Auth uses the `x-api-key` header plus an `anthropic-version` header.

  ## Streaming

  `stream/2` spawns a process that reads Server-Sent Events from the Anthropic
  streaming endpoint and forwards `{:llm_chunk, %LLMChunk{}}` messages to the
  caller. A terminal chunk with `type: :done` signals the end of the stream.

  ## Mock mode

  Set `mock: true` in the `Config` or omit `api_key` to receive deterministic
  synthetic responses without making any API calls. Useful for testing and local
  development.

  ## Usage

      alias Livekit.Agents.LLM.Anthropic
      alias Livekit.Agents.LLM.Anthropic.Config
      alias Livekit.Agents.ChatContext

      config = %Config{api_key: System.get_env("ANTHROPIC_API_KEY")}
      ctx = ChatContext.new() |> ChatContext.add(ChatContext.new_message(:user, ["Hello!"]))

      {:ok, message} = Anthropic.chat(ctx, config: config)
      {:ok, pid} = Anthropic.stream(ctx, config: config)
  """

  use Livekit.Agents.LLM

  require Logger

  alias Livekit.Agents.ChatContext
  alias Livekit.Agents.ChatContext.{ChatMessage, FunctionCall, FunctionCallOutput}
  alias Livekit.Agents.LLM.LLMChunk
  alias Livekit.Agents.Tool.ToolContext

  @anthropic_version "2023-06-01"

  defmodule Config do
    @moduledoc """
    Configuration for the Anthropic LLM provider.

    ## Fields

    - `:api_key` — Anthropic API key. Required unless `:mock` is `true`.
    - `:model` — Anthropic model name (default: `"claude-sonnet-4-20250514"`).
    - `:instructions` — System prompt injected at the start of every conversation.
    - `:temperature` — Sampling temperature 0.0–1.0 (default: `0.7`).
    - `:max_tokens` — Maximum tokens in the response (default: `1024`). Required by the API.
    - `:mock` — When `true`, return synthetic responses without API calls (default: `false`).
    - `:base_url` — Base URL for the Anthropic API (default: `"https://api.anthropic.com"`).
      Override for testing with Bypass.
    """

    @type t :: %__MODULE__{
            api_key: String.t() | nil,
            model: String.t(),
            instructions: String.t(),
            temperature: float(),
            max_tokens: pos_integer(),
            mock: boolean(),
            base_url: String.t()
          }

    defstruct api_key: nil,
              model: "claude-sonnet-4-20250514",
              instructions: "You are a helpful AI assistant.",
              temperature: 0.7,
              max_tokens: 1024,
              mock: false,
              base_url: "https://api.anthropic.com"
  end

  # ---------------------------------------------------------------------------
  # Behaviour callbacks
  # ---------------------------------------------------------------------------

  @doc """
  Returns the capabilities of the Anthropic LLM provider.
  """
  @impl Livekit.Agents.LLM
  @spec capabilities() :: %{
          streaming: boolean(),
          tool_calling: boolean(),
          vision: boolean(),
          max_context_tokens: pos_integer() | nil
        }
  def capabilities do
    %{streaming: true, tool_calling: true, vision: true, max_context_tokens: 200_000}
  end

  @doc """
  Validates a `Config` struct.

  Returns `:ok` when `config.mock` is `true` (no API key required).
  Returns `{:error, :missing_api_key}` when the API key is `nil` or an empty string.
  """
  @impl Livekit.Agents.LLM
  @spec validate_config(Config.t()) :: :ok | {:error, :missing_api_key}
  def validate_config(%Config{mock: true}), do: :ok

  def validate_config(%Config{api_key: key}) when key in [nil, ""],
    do: {:error, :missing_api_key}

  def validate_config(%Config{}), do: :ok

  @doc """
  Sends a `ChatContext` to the Anthropic messages endpoint and returns a single
  response item — either a `ChatMessage` (text response) or a `FunctionCall` (tool call).

  ## Options

  - `:config` — `Config.t()` (required)
  - `:model` — overrides `config.model`
  - `:temperature` — overrides `config.temperature`
  - `:max_tokens` — overrides `config.max_tokens`
  - `:tool_context` — `ToolContext.t()` whose tools are sent in the request body

  ## Returns

  - `{:ok, ChatMessage.t()}` for text responses
  - `{:ok, FunctionCall.t()}` when the model requests a tool call
  - `{:error, reason}` on failure
  """
  @impl Livekit.Agents.LLM
  @spec chat(ChatContext.t(), keyword()) ::
          {:ok, ChatMessage.t() | FunctionCall.t()} | {:error, term()}
  def chat(%ChatContext{} = ctx, opts \\ []) do
    config = Keyword.fetch!(opts, :config)

    if mock_mode?(config) do
      {:ok, mock_chat_response()}
    else
      do_chat(ctx, config, opts)
    end
  end

  @doc """
  Starts a streaming LLM response process.

  The spawned process sends `{:llm_chunk, %LLMChunk{type: :text, content: text}}` messages
  to the caller for each token fragment, followed by a terminal
  `{:llm_chunk, %LLMChunk{type: :done}}` message when the stream ends.

  On error the process sends `{:error, reason}` to the caller.

  ## Options

  Same as `chat/2`.
  """
  @impl Livekit.Agents.LLM
  @spec stream(ChatContext.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def stream(%ChatContext{} = ctx, opts \\ []) do
    config = Keyword.fetch!(opts, :config)
    subscriber = self()

    if mock_mode?(config) do
      pid =
        spawn(fn ->
          send(subscriber, {:llm_chunk, %LLMChunk{type: :text, content: "Mock"}})
          send(subscriber, {:llm_chunk, %LLMChunk{type: :done}})
        end)

      {:ok, pid}
    else
      pid = spawn(fn -> do_stream(ctx, config, opts, subscriber) end)
      {:ok, pid}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — HTTP (chat)
  # ---------------------------------------------------------------------------

  defp do_chat(%ChatContext{} = ctx, %Config{} = config, opts) do
    model = Keyword.get(opts, :model, config.model)
    temperature = Keyword.get(opts, :temperature, config.temperature)
    max_tokens = Keyword.get(opts, :max_tokens, config.max_tokens)
    tool_context = Keyword.get(opts, :tool_context)

    # Estimate max messages to keep: ~100 tokens per message, cap at 100 entries
    max_messages = min(div(200_000, 100), 100)
    truncated_ctx = ChatContext.truncate(ctx, max(max_messages, 20))

    {system_prompt, messages} = to_anthropic_messages(truncated_ctx.items, config.instructions)

    body =
      %{
        model: model,
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens,
        system: system_prompt
      }
      |> maybe_add_tools(tool_context)

    client = build_client(config)

    case Tesla.post(client, "/v1/messages", body) do
      {:ok, env} -> parse_chat_response(env)
      {:error, reason} -> {:error, {:request_failed, reason}}
    end
  end

  defp maybe_add_tools(body, nil), do: body

  defp maybe_add_tools(body, %ToolContext{} = tool_context) do
    Map.put(body, :tools, ToolContext.to_anthropic_tools(tool_context))
  end

  # ---------------------------------------------------------------------------
  # Private — HTTP (stream)
  # ---------------------------------------------------------------------------

  defp do_stream(%ChatContext{} = ctx, %Config{} = config, opts, subscriber) do
    model = Keyword.get(opts, :model, config.model)
    temperature = Keyword.get(opts, :temperature, config.temperature)
    max_tokens = Keyword.get(opts, :max_tokens, config.max_tokens)
    tool_context = Keyword.get(opts, :tool_context)

    # Estimate max messages to keep: ~100 tokens per message, cap at 100 entries
    max_messages = min(div(200_000, 100), 100)
    truncated_ctx = ChatContext.truncate(ctx, max(max_messages, 20))

    {system_prompt, messages} = to_anthropic_messages(truncated_ctx.items, config.instructions)

    body =
      %{
        model: model,
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens,
        system: system_prompt,
        stream: true
      }
      |> maybe_add_tools(tool_context)

    client = build_stream_client(config)

    case Tesla.post(client, "/v1/messages", body) do
      {:ok, %Tesla.Env{status: 200, body: raw_body}} ->
        process_sse_body(raw_body, subscriber)
        send(subscriber, {:llm_chunk, %LLMChunk{type: :done}})

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        send(subscriber, {:error, {:api_error, status, error_body}})

      {:error, reason} ->
        send(subscriber, {:error, {:request_failed, reason}})
    end
  end

  defp process_sse_body(body, subscriber) when is_binary(body) do
    body
    |> String.split("\n")
    |> Enum.each(fn line -> handle_sse_line(line, subscriber) end)
  end

  defp handle_sse_line(line, subscriber) do
    case parse_sse_line(line) do
      {:text, content} ->
        send(subscriber, {:llm_chunk, %LLMChunk{type: :text, content: content}})

      :skip ->
        :ok
    end
  end

  # Anthropic SSE events: data lines carry JSON with "type" field
  # Relevant types: "content_block_delta" (text tokens), "message_stop" (terminal)
  defp parse_sse_line("data: " <> json_str) do
    case Jason.decode(json_str) do
      {:ok,
       %{"type" => "content_block_delta", "delta" => %{"type" => "text_delta", "text" => text}}}
      when is_binary(text) and text != "" ->
        {:text, text}

      _ ->
        :skip
    end
  end

  defp parse_sse_line(_), do: :skip

  # ---------------------------------------------------------------------------
  # Private — response parsing
  # ---------------------------------------------------------------------------

  defp parse_chat_response(%Tesla.Env{status: 200, body: body}) do
    content_blocks = body["content"] || []

    # Check for tool_use blocks first
    tool_use_block = Enum.find(content_blocks, &(&1["type"] == "tool_use"))

    if tool_use_block do
      function_call =
        ChatContext.new_function_call(
          tool_use_block["id"],
          tool_use_block["name"],
          Jason.encode!(tool_use_block["input"] || %{})
        )

      {:ok, function_call}
    else
      # Collect all text blocks
      text =
        content_blocks
        |> Enum.filter(&(&1["type"] == "text"))
        |> Enum.map_join("", & &1["text"])

      {:ok, ChatContext.new_message(:assistant, [text])}
    end
  end

  defp parse_chat_response(%Tesla.Env{status: status, body: body}) do
    {:error, {:api_error, status, body}}
  end

  # ---------------------------------------------------------------------------
  # Private — message conversion
  # ---------------------------------------------------------------------------

  # Anthropic Messages API format:
  # - System prompt is a top-level field (extracted from :system role messages)
  # - Messages array only contains :user and :assistant roles
  # - Tool results use role "user" with content type "tool_result"
  # - Tool use is signalled by assistant message with "tool_use" content block
  defp to_anthropic_messages(items, default_system) do
    # Extract system messages and build the system prompt string
    system_messages =
      items
      |> Enum.filter(fn
        %ChatMessage{role: :system} -> true
        _ -> false
      end)
      |> Enum.map_join("\n", &content_to_string(&1.content))

    system_prompt =
      if system_messages == "" do
        default_system
      else
        system_messages
      end

    # Convert non-system items to Anthropic message format
    messages =
      items
      |> Enum.reject(fn
        %ChatMessage{role: :system} -> true
        _ -> false
      end)
      |> Enum.map(&item_to_anthropic_message/1)
      |> merge_consecutive_same_role()

    {system_prompt, messages}
  end

  defp item_to_anthropic_message(%ChatMessage{role: role, content: parts})
       when role in [:user, :assistant] do
    %{"role" => Atom.to_string(role), "content" => content_to_string(parts)}
  end

  defp item_to_anthropic_message(%FunctionCall{call_id: id, name: name, arguments: args}) do
    input =
      case Jason.decode(args) do
        {:ok, decoded} -> decoded
        _ -> %{}
      end

    %{
      "role" => "assistant",
      "content" => [
        %{
          "type" => "tool_use",
          "id" => id,
          "name" => name,
          "input" => input
        }
      ]
    }
  end

  defp item_to_anthropic_message(%FunctionCallOutput{
         call_id: id,
         output: out,
         is_error: is_error
       }) do
    content_block =
      if is_error do
        %{"type" => "tool_result", "tool_use_id" => id, "content" => out, "is_error" => true}
      else
        %{"type" => "tool_result", "tool_use_id" => id, "content" => out}
      end

    %{"role" => "user", "content" => [content_block]}
  end

  # Anthropic requires alternating user/assistant roles. Merge consecutive messages
  # with the same role into a single message with combined content.
  defp merge_consecutive_same_role([]), do: []

  defp merge_consecutive_same_role(messages) do
    messages
    |> Enum.reduce([], &merge_or_prepend/2)
    |> Enum.reverse()
  end

  defp merge_or_prepend(msg, []), do: [msg]

  defp merge_or_prepend(msg, [prev | rest]) do
    if prev["role"] == msg["role"] do
      [merge_messages(prev, msg) | rest]
    else
      [msg | [prev | rest]]
    end
  end

  defp merge_messages(%{"role" => role, "content" => prev_content}, %{"content" => new_content}) do
    merged_content =
      case {prev_content, new_content} do
        {p, n} when is_binary(p) and is_binary(n) ->
          p <> "\n" <> n

        {p, n} when is_binary(p) ->
          [%{"type" => "text", "text" => p}] ++ ensure_list(n)

        {p, n} when is_binary(n) ->
          ensure_list(p) ++ [%{"type" => "text", "text" => n}]

        {p, n} ->
          ensure_list(p) ++ ensure_list(n)
      end

    %{"role" => role, "content" => merged_content}
  end

  defp ensure_list(x) when is_list(x), do: x
  defp ensure_list(x), do: [x]

  defp content_to_string([single]) when is_binary(single), do: single
  defp content_to_string(parts), do: Jason.encode!(parts)

  # ---------------------------------------------------------------------------
  # Private — HTTP clients
  # ---------------------------------------------------------------------------

  defp build_client(%Config{api_key: key, base_url: base_url}) do
    middleware = [
      {Tesla.Middleware.BaseUrl, base_url},
      {Tesla.Middleware.Headers,
       [
         {"x-api-key", key},
         {"anthropic-version", @anthropic_version},
         {"content-type", "application/json"}
       ]},
      Tesla.Middleware.JSON
    ]

    Tesla.client(middleware, Tesla.Adapter.Hackney)
  end

  defp build_stream_client(%Config{api_key: key, base_url: base_url}) do
    middleware = [
      {Tesla.Middleware.BaseUrl, base_url},
      {Tesla.Middleware.Headers,
       [
         {"x-api-key", key},
         {"anthropic-version", @anthropic_version},
         {"content-type", "application/json"}
       ]},
      Tesla.Middleware.JSON
    ]

    Tesla.client(middleware, {Tesla.Adapter.Hackney, [recv_timeout: 60_000]})
  end

  # ---------------------------------------------------------------------------
  # Private — helpers
  # ---------------------------------------------------------------------------

  defp mock_mode?(%Config{mock: true}), do: true
  defp mock_mode?(%Config{api_key: key}) when key in [nil, ""], do: true
  defp mock_mode?(%Config{}), do: false

  defp mock_chat_response do
    ChatContext.new_message(:assistant, ["I'm a mock LLM response."])
  end
end

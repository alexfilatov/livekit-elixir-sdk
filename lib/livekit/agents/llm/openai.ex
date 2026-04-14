defmodule Livekit.Agents.LLM.OpenAI do
  @moduledoc """
  OpenAI Large Language Model provider for LiveKit agents.

  Pure functional module implementing `@behaviour Livekit.Agents.LLM`. Sends HTTP
  POST requests to `/v1/chat/completions` via Tesla, converts `ChatContext` items to
  the OpenAI messages wire format, and parses responses into `ChatMessage` or
  `FunctionCall` structs.

  ## Streaming

  `stream/2` spawns a process that reads Server-Sent Events from the OpenAI streaming
  endpoint and forwards `{:llm_chunk, %LLMChunk{}}` messages to the caller. A terminal
  chunk with `type: :done` signals the end of the stream.

  ## Mock mode

  Set `mock: true` in the `Config` or omit `api_key` to receive deterministic synthetic
  responses without making any API calls. Useful for testing and local development.

  ## Usage

      alias Livekit.Agents.LLM.OpenAI
      alias Livekit.Agents.LLM.OpenAI.Config
      alias Livekit.Agents.ChatContext

      config = %Config{api_key: System.get_env("OPENAI_API_KEY")}
      ctx = ChatContext.new() |> ChatContext.add(ChatContext.new_message(:user, ["Hello!"]))

      {:ok, message} = OpenAI.chat(ctx, config: config)
      {:ok, pid} = OpenAI.stream(ctx, config: config)
  """

  use Livekit.Agents.LLM

  require Logger

  alias Livekit.Agents.ChatContext
  alias Livekit.Agents.ChatContext.{ChatMessage, FunctionCall, FunctionCallOutput}
  alias Livekit.Agents.LLM.LLMChunk
  alias Livekit.Agents.Tool.ToolContext

  defmodule Config do
    @moduledoc """
    Configuration for the OpenAI LLM provider.

    ## Fields

    - `:api_key` — OpenAI API key. Required unless `:mock` is `true`.
    - `:model` — OpenAI model name (default: `"gpt-4o-mini"`).
    - `:instructions` — System prompt injected at the start of every conversation.
    - `:temperature` — Sampling temperature 0.0–2.0 (default: `0.7`).
    - `:max_tokens` — Maximum tokens in the response (default: `1000`).
    - `:mock` — When `true`, return synthetic responses without API calls (default: `false`).
    - `:base_url` — Base URL for the OpenAI API (default: `"https://api.openai.com"`).
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
              model: "gpt-4o-mini",
              instructions: "You are a helpful AI assistant.",
              temperature: 0.7,
              max_tokens: 1000,
              mock: false,
              base_url: "https://api.openai.com"
  end

  # ---------------------------------------------------------------------------
  # Behaviour callbacks
  # ---------------------------------------------------------------------------

  @doc """
  Returns the capabilities of the OpenAI LLM provider.
  """
  @impl Livekit.Agents.LLM
  @spec capabilities() :: %{
          streaming: boolean(),
          tool_calling: boolean(),
          vision: boolean(),
          max_context_tokens: pos_integer() | nil
        }
  def capabilities do
    %{streaming: true, tool_calling: true, vision: false, max_context_tokens: 128_000}
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
  Sends a `ChatContext` to the OpenAI chat completions endpoint and returns a single
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
    max_messages = min(div(128_000, 100), 100)
    truncated_ctx = ChatContext.truncate(ctx, max(max_messages, 20))
    messages = to_openai_messages(truncated_ctx.items)

    body =
      %{
        model: model,
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens
      }
      |> maybe_add_tools(tool_context)

    client = build_client(config)

    case Tesla.post(client, "/v1/chat/completions", body) do
      {:ok, env} -> parse_chat_response(env)
      {:error, reason} -> {:error, {:request_failed, reason}}
    end
  end

  defp maybe_add_tools(body, nil), do: body

  defp maybe_add_tools(body, %ToolContext{} = tool_context) do
    Map.put(body, :tools, ToolContext.to_openai_tools(tool_context))
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
    max_messages = min(div(128_000, 100), 100)
    truncated_ctx = ChatContext.truncate(ctx, max(max_messages, 20))
    messages = to_openai_messages(truncated_ctx.items)

    body =
      %{
        model: model,
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens,
        stream: true
      }
      |> maybe_add_tools(tool_context)

    client = build_stream_client(config)

    case Tesla.post(client, "/v1/chat/completions", body) do
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

  defp parse_sse_line("data: [DONE]"), do: :skip

  defp parse_sse_line("data: " <> json_str) do
    case Jason.decode(json_str) do
      {:ok, %{"choices" => [%{"delta" => delta} | _]}} ->
        case delta["content"] do
          content when is_binary(content) and content != "" ->
            {:text, content}

          _ ->
            :skip
        end

      _ ->
        :skip
    end
  end

  defp parse_sse_line(_), do: :skip

  # ---------------------------------------------------------------------------
  # Private — response parsing
  # ---------------------------------------------------------------------------

  defp parse_chat_response(%Tesla.Env{status: 200, body: body}) do
    choice = List.first(body["choices"])
    message = choice["message"]

    case message["tool_calls"] do
      [_ | _] = tool_calls ->
        function_calls =
          Enum.map(tool_calls, fn tc ->
            ChatContext.new_function_call(
              tc["id"],
              tc["function"]["name"],
              tc["function"]["arguments"]
            )
          end)

        # Return the first FunctionCall so the caller receives a single item per the
        # behaviour contract. All FunctionCall structs are available in the ChatContext
        # when the Tool.run loop adds them there before calling chat/2 again.
        {:ok, List.first(function_calls)}

      _ ->
        content = message["content"] || ""
        {:ok, ChatContext.new_message(:assistant, [content])}
    end
  end

  defp parse_chat_response(%Tesla.Env{status: status, body: body}) do
    {:error, {:api_error, status, body}}
  end

  # ---------------------------------------------------------------------------
  # Private — message conversion
  # ---------------------------------------------------------------------------

  defp to_openai_messages(items) do
    Enum.map(items, &item_to_openai_message/1)
  end

  defp item_to_openai_message(%ChatMessage{role: role, content: parts}) do
    %{"role" => Atom.to_string(role), "content" => content_to_string(parts)}
  end

  defp item_to_openai_message(%FunctionCall{call_id: id, name: name, arguments: args}) do
    %{
      "role" => "assistant",
      "tool_calls" => [
        %{
          "id" => id,
          "type" => "function",
          "function" => %{"name" => name, "arguments" => args}
        }
      ]
    }
  end

  defp item_to_openai_message(%FunctionCallOutput{call_id: id, name: name, output: out}) do
    %{"role" => "tool", "tool_call_id" => id, "name" => name, "content" => out}
  end

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
         {"Authorization", "Bearer #{key}"},
         {"Content-Type", "application/json"}
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
         {"Authorization", "Bearer #{key}"},
         {"Content-Type", "application/json"}
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

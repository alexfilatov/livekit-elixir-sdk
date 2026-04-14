defmodule Livekit.Agents.Tool do
  @moduledoc """
  Tool system for LLM function calling.

  Provides three components:

  - `ToolSpec` — a tool definition with name, description, parameters schema, and handler function
  - `ToolContext` — a registry of `ToolSpec` entries with O(1) lookup and OpenAI schema generation
  - `ToolError` — exception raised on handler failure, caught and converted to `FunctionCallOutput(is_error: true)`

  ## Usage

      alias Livekit.Agents.Tool
      alias Livekit.Agents.Tool.{ToolSpec, ToolContext}

      weather_tool = ToolSpec.new(
        name: "get_weather",
        description: "Returns current weather for a city",
        parameters: %{
          "type" => "object",
          "properties" => %{"city" => %{"type" => "string"}},
          "required" => ["city"]
        },
        handler: fn %{"city" => city} -> {:ok, "Sunny in \#{city}"} end
      )

      tool_ctx = ToolContext.new([weather_tool])

      {:ok, final_ctx} = Tool.run(MyLLM, chat_ctx, tool_context: tool_ctx, max_tool_steps: 5)

  See `run/3` for the execution loop.
  """

  alias Livekit.Agents.ChatContext
  alias Livekit.Agents.ChatContext.FunctionCall
  alias Livekit.Agents.Tool.{ToolContext, ToolError}

  defmodule ToolSpec do
    @moduledoc """
    Specification for a single tool available to the LLM.

    ## Fields

    - `:name` — tool name as it appears in LLM function calls (e.g. `"get_weather"`)
    - `:description` — human-readable description the LLM uses to decide when to call this tool
    - `:parameters` — JSON Schema map describing accepted parameters (OpenAI `parameters` format)
    - `:handler` — `(args :: map() -> {:ok, String.t()} | {:error, String.t()})` function

    ## Example

        ToolSpec.new(
          name: "get_weather",
          description: "Returns current weather for a city",
          parameters: %{
            "type" => "object",
            "properties" => %{
              "city" => %{"type" => "string", "description" => "City name"}
            },
            "required" => ["city"]
          },
          handler: fn %{"city" => city} -> {:ok, "Sunny in \#{city}"} end
        )
    """

    @type handler :: (map() -> {:ok, String.t()} | {:error, String.t()})

    @type t :: %__MODULE__{
            name: String.t(),
            description: String.t(),
            parameters: map(),
            handler: handler()
          }

    defstruct [:name, :description, :parameters, :handler]

    @doc """
    Creates a new `ToolSpec` from a keyword list.

    Required keys: `:name`, `:description`, `:parameters`, `:handler`.
    """
    @spec new(keyword()) :: t()
    def new(opts) do
      %__MODULE__{
        name: Keyword.fetch!(opts, :name),
        description: Keyword.fetch!(opts, :description),
        parameters: Keyword.fetch!(opts, :parameters),
        handler: Keyword.fetch!(opts, :handler)
      }
    end

    @doc """
    Converts the `ToolSpec` to an OpenAI function-calling schema map.

    Output format:
    ```json
    {
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "Returns current weather for a city",
        "parameters": { ... }
      }
    }
    ```
    """
    @spec to_openai_schema(t()) :: map()
    def to_openai_schema(%__MODULE__{} = spec) do
      %{
        "type" => "function",
        "function" => %{
          "name" => spec.name,
          "description" => spec.description,
          "parameters" => spec.parameters
        }
      }
    end
  end

  defmodule ToolContext do
    @moduledoc """
    A registry of `ToolSpec` entries available for LLM function calling.

    ## Example

        ctx = ToolContext.new([weather_spec, calculator_spec])
        {:ok, spec} = ToolContext.lookup(ctx, "get_weather")
        schemas = ToolContext.to_openai_tools(ctx)
    """

    alias Livekit.Agents.Tool.ToolSpec

    @type t :: %__MODULE__{
            tools: %{String.t() => ToolSpec.t()}
          }

    defstruct tools: %{}

    @doc """
    Creates a new `ToolContext` from a list of `ToolSpec` entries.
    Tools are indexed by name for O(1) lookup.
    """
    @spec new([ToolSpec.t()]) :: t()
    def new(specs) when is_list(specs) do
      tools = Map.new(specs, fn spec -> {spec.name, spec} end)
      %__MODULE__{tools: tools}
    end

    @doc """
    Looks up a `ToolSpec` by name.

    Returns `{:ok, spec}` if found, `{:error, :not_found}` otherwise.
    """
    @spec lookup(t(), String.t()) :: {:ok, ToolSpec.t()} | {:error, :not_found}
    def lookup(%__MODULE__{tools: tools}, name) when is_binary(name) do
      case Map.fetch(tools, name) do
        {:ok, spec} -> {:ok, spec}
        :error -> {:error, :not_found}
      end
    end

    @doc """
    Returns all tools as a list of OpenAI function-calling schema maps.

    Pass the result directly to an OpenAI `tools:` parameter.
    """
    @spec to_openai_tools(t()) :: [map()]
    def to_openai_tools(%__MODULE__{tools: tools}) do
      tools
      |> Map.values()
      |> Enum.map(&ToolSpec.to_openai_schema/1)
    end
  end

  defmodule ToolError do
    @moduledoc """
    Exception raised by the tool execution loop when a handler returns
    `{:error, reason}` or raises itself.

    The execution loop catches `ToolError` and converts it into a
    `FunctionCallOutput` with `is_error: true` so the LLM can handle the
    failure gracefully.
    """

    defexception [:message, :call_id, :tool_name, :reason]

    @type t :: %__MODULE__{
            message: String.t(),
            call_id: String.t(),
            tool_name: String.t(),
            reason: term()
          }

    @impl true
    def exception(opts) do
      call_id = Keyword.fetch!(opts, :call_id)
      tool_name = Keyword.fetch!(opts, :tool_name)
      reason = Keyword.fetch!(opts, :reason)

      %__MODULE__{
        message: "Tool #{tool_name} (call_id=#{call_id}) failed: #{inspect(reason)}",
        call_id: call_id,
        tool_name: tool_name,
        reason: reason
      }
    end
  end

  @doc """
  Runs the LLM tool-calling execution loop.

  Calls `llm_module.chat(chat_ctx, opts)` and checks the resulting ChatContext
  for any `FunctionCall` items that were appended by the provider. For each
  `FunctionCall`:

  1. Looks up the handler in `tool_context` by tool name.
  2. Decodes `FunctionCall.arguments` via `Jason.decode!/1`.
  3. Calls the handler with the decoded args map.
  4. On `{:ok, result}`: creates a `FunctionCallOutput(is_error: false)` and appends it to the context.
  5. On `{:error, reason}`: raises `ToolError` which is caught and converted to a `FunctionCallOutput(is_error: true)`.
  6. Feeds the updated context back to the LLM and repeats.

  The loop stops when either:
  - The LLM response contains no `FunctionCall` items (natural completion), or
  - The step counter reaches `max_tool_steps` (safety cap).

  ## Options

  - `:tool_context` — `ToolContext.t()` registry of available tools (required)
  - `:max_tool_steps` — maximum tool call iterations before stopping (default: `10`)
  - Any other opts are forwarded to `llm_module.chat/2`

  ## Returns

  `{:ok, ChatContext.t()}` — the final context with all messages and tool outputs appended.
  `{:error, reason}` — if the LLM call itself fails (not a tool handler failure).

  ## Example

      {:ok, ctx} = Tool.run(MyLLM, chat_ctx,
        tool_context: tool_ctx,
        max_tool_steps: 5,
        model: "gpt-4o"
      )
  """
  @spec run(module(), ChatContext.t(), keyword()) ::
          {:ok, ChatContext.t()} | {:error, term()}
  def run(llm_module, chat_ctx, opts \\ []) do
    tool_context = Keyword.fetch!(opts, :tool_context)
    max_tool_steps = Keyword.get(opts, :max_tool_steps, 10)
    llm_opts = Keyword.drop(opts, [:tool_context, :max_tool_steps])

    do_run(llm_module, chat_ctx, tool_context, max_tool_steps, 0, llm_opts)
  end

  # Private Helpers

  defp do_run(llm_module, chat_ctx, tool_context, max_tool_steps, step, llm_opts) do
    case llm_module.chat(chat_ctx, llm_opts) do
      {:error, reason} ->
        {:error, reason}

      {:ok, response_item} ->
        # Provider appends its response to the context; if it doesn't, we do it here.
        # Detect whether the provider already appended by checking if the item is
        # in ctx.items. If not, append it.
        updated_ctx = maybe_add_response(chat_ctx, response_item)

        # Collect any FunctionCall items just added (tail of items not in original ctx)
        function_calls = extract_new_function_calls(chat_ctx, updated_ctx)

        cond do
          function_calls == [] ->
            # No tool calls — natural completion
            {:ok, updated_ctx}

          step >= max_tool_steps ->
            # Safety cap reached — return current context without executing more calls
            {:ok, updated_ctx}

          true ->
            # Execute each function call and append outputs
            ctx_with_outputs = execute_all_calls(function_calls, updated_ctx, tool_context)

            do_run(llm_module, ctx_with_outputs, tool_context, max_tool_steps, step + 1, llm_opts)
        end
    end
  end

  defp maybe_add_response(original_ctx, response_item) do
    # Check by struct identity — if the exact item is already in the context, skip.
    if Enum.member?(original_ctx.items, response_item) do
      original_ctx
    else
      ChatContext.add(original_ctx, response_item)
    end
  end

  defp extract_new_function_calls(original_ctx, updated_ctx) do
    original_ids = MapSet.new(original_ctx.items, & &1.id)

    updated_ctx.items
    |> Enum.reject(fn item -> MapSet.member?(original_ids, item.id) end)
    |> Enum.filter(&match?(%FunctionCall{}, &1))
  end

  defp execute_all_calls(function_calls, ctx, tool_context) do
    Enum.reduce(function_calls, ctx, fn fc, acc_ctx ->
      output = execute_call(fc, tool_context)
      ChatContext.add(acc_ctx, output)
    end)
  end

  defp execute_call(%FunctionCall{} = fc, tool_context) do
    result =
      try do
        case ToolContext.lookup(tool_context, fc.name) do
          {:error, :not_found} ->
            raise ToolError,
              call_id: fc.call_id,
              tool_name: fc.name,
              reason: :not_found

          {:ok, spec} ->
            args = Jason.decode!(fc.arguments)

            case spec.handler.(args) do
              {:ok, output} ->
                {:ok, output}

              {:error, reason} ->
                raise ToolError,
                  call_id: fc.call_id,
                  tool_name: fc.name,
                  reason: reason
            end
        end
      rescue
        err in [ToolError] ->
          {:error, err}

        err ->
          {:error,
           %ToolError{
             message: "Unexpected error in tool #{fc.name}: #{inspect(err)}",
             call_id: fc.call_id,
             tool_name: fc.name,
             reason: err
           }}
      end

    case result do
      {:ok, output} ->
        ChatContext.new_function_call_output(fc.call_id, fc.name, output, false)

      {:error, %ToolError{} = err} ->
        ChatContext.new_function_call_output(fc.call_id, fc.name, err.message, true)
    end
  end
end

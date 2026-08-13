defmodule Livekit.Agents.ChatContext do
  @moduledoc """
  Typed conversation context for LLM providers.

  Maintains an ordered (oldest-first) list of `chat_item` entries:
  `ChatMessage`, `FunctionCall`, and `FunctionCallOutput`. All items
  carry a unique `id` and a `created_at` timestamp.

  ## Usage

      ctx = ChatContext.new()
      msg = ChatContext.new_message(:user, ["Hello, who are you?"])
      ctx = ChatContext.add(ctx, msg)
      ctx = ChatContext.truncate(ctx, 20)

  ## Truncation invariant

  `truncate/2` preserves all leading system messages and drops orphaned
  `FunctionCallOutput` entries at the truncation boundary.
  """

  defmodule ChatMessage do
    @moduledoc """
    A single conversation message.

    ## Roles

    - `:system` — system prompt (never dropped by truncation)
    - `:user` — user turn
    - `:assistant` — assistant/LLM turn
    - `:tool` — tool result message

    ## Multi-modal content

    `content` is a list to support mixed text and structured data:

        # Text only
        ["Hello there"]

        # Multi-modal (text + image ref)
        ["Describe this image:", %{"type" => "image_url", "url" => "https://..."}]

    ## Jason encoding

    `Jason.encode!/1` produces ISO 8601 string for `created_at` and string for `role`.
    Decoding does NOT reconstruct the struct; use a constructor for that.
    """

    @type role :: :system | :user | :assistant | :tool
    @type content_item :: String.t() | map()

    @type t :: %__MODULE__{
            id: String.t(),
            role: role(),
            content: [content_item()],
            interrupted: boolean(),
            created_at: DateTime.t()
          }

    defstruct [:id, :role, :content, :interrupted, :created_at]
  end

  defmodule FunctionCall do
    @moduledoc """
    A tool/function call request from the LLM.

    `arguments` is stored as a JSON-encoded string, matching the OpenAI API
    response format. Callers decode with `Jason.decode!/1` before executing.
    """

    @type t :: %__MODULE__{
            id: String.t(),
            call_id: String.t(),
            name: String.t(),
            arguments: String.t(),
            created_at: DateTime.t()
          }

    defstruct [:id, :call_id, :name, :arguments, :created_at]
  end

  defmodule FunctionCallOutput do
    @moduledoc """
    Result of executing a tool call, to be fed back to the LLM.

    `is_error` defaults to `false`. Set to `true` when the tool handler
    returned an error so the LLM can handle the failure gracefully.
    """

    @type t :: %__MODULE__{
            id: String.t(),
            call_id: String.t(),
            name: String.t(),
            output: String.t(),
            is_error: boolean(),
            created_at: DateTime.t()
          }

    defstruct [:id, :call_id, :name, :output, :created_at, is_error: false]
  end

  defimpl Jason.Encoder, for: Livekit.Agents.ChatContext.ChatMessage do
    @doc false
    def encode(msg, opts) do
      Jason.Encode.map(
        %{
          "id" => msg.id,
          "role" => Atom.to_string(msg.role),
          "content" => msg.content,
          "interrupted" => msg.interrupted,
          "created_at" => DateTime.to_iso8601(msg.created_at)
        },
        opts
      )
    end
  end

  defimpl Jason.Encoder, for: Livekit.Agents.ChatContext.FunctionCall do
    @doc false
    def encode(fc, opts) do
      Jason.Encode.map(
        %{
          "id" => fc.id,
          "call_id" => fc.call_id,
          "name" => fc.name,
          "arguments" => fc.arguments,
          "created_at" => DateTime.to_iso8601(fc.created_at)
        },
        opts
      )
    end
  end

  defimpl Jason.Encoder, for: Livekit.Agents.ChatContext.FunctionCallOutput do
    @doc false
    def encode(fco, opts) do
      Jason.Encode.map(
        %{
          "id" => fco.id,
          "call_id" => fco.call_id,
          "name" => fco.name,
          "output" => fco.output,
          "is_error" => fco.is_error,
          "created_at" => DateTime.to_iso8601(fco.created_at)
        },
        opts
      )
    end
  end

  @type chat_item :: ChatMessage.t() | FunctionCall.t() | FunctionCallOutput.t()

  @type t :: %__MODULE__{
          items: [chat_item()]
        }

  defstruct items: []

  @doc """
  Creates an empty `ChatContext`.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Creates a new `ChatMessage` with a generated id and current timestamp.

  `role` must be one of `:system`, `:user`, `:assistant`, or `:tool`.
  `content` is a list of strings and/or maps for multi-modal support.

  ## Examples

      iex> msg = ChatContext.new_message(:user, ["Hello!"])
      iex> msg.role
      :user
      iex> msg.content
      ["Hello!"]
  """
  @spec new_message(ChatMessage.role(), [ChatMessage.content_item()]) :: ChatMessage.t()
  def new_message(role, content)
      when role in [:system, :user, :assistant, :tool] and is_list(content) do
    %ChatMessage{
      id: generate_id(),
      role: role,
      content: content,
      interrupted: false,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Creates a new `FunctionCall` with a generated id and current timestamp.

  `call_id` is the provider-assigned call identifier (e.g., from OpenAI tool call response).
  `name` is the function/tool name. `arguments` is a JSON-encoded argument string.

  ## Examples

      iex> fc = ChatContext.new_function_call("call_abc", "get_weather", "{\"city\": \"London\"}")
      iex> fc.name
      "get_weather"
  """
  @spec new_function_call(String.t(), String.t(), String.t()) :: FunctionCall.t()
  def new_function_call(call_id, name, arguments)
      when is_binary(call_id) and is_binary(name) and is_binary(arguments) do
    %FunctionCall{
      id: generate_id(),
      call_id: call_id,
      name: name,
      arguments: arguments,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Creates a new `FunctionCallOutput` with a generated id and current timestamp.

  `call_id` must match the `call_id` of the originating `FunctionCall`.
  `output` is the result string. `is_error` defaults to `false`.

  ## Examples

      iex> fco = ChatContext.new_function_call_output("call_abc", "get_weather", "Cloudy, 12°C")
      iex> fco.is_error
      false
  """
  @spec new_function_call_output(String.t(), String.t(), String.t(), boolean()) ::
          FunctionCallOutput.t()
  def new_function_call_output(call_id, name, output, is_error \\ false)
      when is_binary(call_id) and is_binary(name) and is_binary(output) and
             is_boolean(is_error) do
    %FunctionCallOutput{
      id: generate_id(),
      call_id: call_id,
      name: name,
      output: output,
      is_error: is_error,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Appends a `chat_item` to the context. Items are stored oldest-first.

  O(n) due to list append. Acceptable for voice agent workloads (dozens to
  hundreds of messages). For very high-frequency usage consider storing
  reversed and flipping only on read.
  """
  @spec add(t(), chat_item()) :: t()
  def add(%__MODULE__{} = ctx, item) do
    %{ctx | items: ctx.items ++ [item]}
  end

  @doc """
  Returns only the `ChatMessage` items from the context, in order.
  """
  @spec messages(t()) :: [ChatMessage.t()]
  def messages(%__MODULE__{} = ctx) do
    Enum.filter(ctx.items, &match?(%ChatMessage{}, &1))
  end

  @doc """
  Truncates the context to at most `max_items` non-system items.

  Invariants:
  - Leading system messages are always preserved (never truncated).
  - After slicing, any leading `FunctionCallOutput` whose `call_id` has no
    corresponding `FunctionCall` in the remaining items is dropped (orphan
    prevention). This avoids sending contexts that confuse the LLM.

  `max_items` must be a positive integer.
  """
  @spec truncate(t(), pos_integer()) :: t()
  def truncate(%__MODULE__{} = ctx, max_items)
      when is_integer(max_items) and max_items > 0 do
    {system_items, rest} =
      Enum.split_while(ctx.items, fn
        %ChatMessage{role: :system} -> true
        _ -> false
      end)

    truncated_rest =
      rest
      |> Enum.take(-max_items)
      |> drop_leading_orphaned_outputs()

    %{ctx | items: system_items ++ truncated_rest}
  end

  @doc """
  Returns a shallow copy of the context.

  The `items` list is a new list containing the same item structs
  (structs are immutable in Elixir, so no deep copy is needed).
  """
  @spec copy(t()) :: t()
  def copy(%__MODULE__{} = ctx), do: %__MODULE__{items: ctx.items}

  @doc """
  Merges items from `other` into `ctx`, skipping any item whose `id`
  already exists in `ctx`. The resulting items list is sorted by
  `created_at` ascending (oldest first).
  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{} = ctx, %__MODULE__{} = other) do
    existing_ids = MapSet.new(ctx.items, & &1.id)
    new_items = Enum.reject(other.items, &MapSet.member?(existing_ids, &1.id))
    all_items = ctx.items ++ new_items
    sorted = Enum.sort_by(all_items, & &1.created_at, DateTime)
    %{ctx | items: sorted}
  end

  # Private Helpers

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp drop_leading_orphaned_outputs(items) do
    call_ids =
      items
      |> Enum.filter(&match?(%FunctionCall{}, &1))
      |> MapSet.new(& &1.call_id)

    Enum.drop_while(items, fn
      %FunctionCallOutput{call_id: cid} -> not MapSet.member?(call_ids, cid)
      _ -> false
    end)
  end
end

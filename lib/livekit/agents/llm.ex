defmodule Livekit.Agents.LLM do
  @moduledoc """
  Behaviour contract for Large Language Model providers.

  Any module that `use Livekit.Agents.LLM` becomes a conforming LLM provider
  and can be plugged into the voice pipeline via the `{module, config}` tuple.

  Note: `chat_context` is typed as `term()` in Phase 1. It will be tightened to
  `Livekit.Agents.ChatContext.t()` in Phase 2 when the ChatContext module is defined.

  ## Batch usage

      {:ok, message} = MyLLM.chat(context, model: "gpt-4o")
      # message is %{role: :assistant, content: "Hello, how can I help?"}

  ## Streaming usage

      {:ok, stream_pid} = MyLLM.stream(context, model: "gpt-4o")
      # stream_pid sends {:llm_chunk, %Livekit.Agents.LLM.LLMChunk{}} to self()
      # A chunk with type: :done signals end of stream

  ## Implementing a provider

      defmodule MyLLM do
        use Livekit.Agents.LLM

        @impl true
        def chat(_context, _opts) do
          {:ok, %{role: :assistant, content: "Hello!"}}
        end

        @impl true
        def capabilities do
          %{streaming: false, tool_calling: false, vision: false, max_context_tokens: 4096}
        end
      end

  Optional callbacks (`stream/2`, `validate_config/1`) are not required for batch-only providers.
  Use `function_exported?(module, :stream, 2)` to check streaming support at runtime.

  LLM providers handling API keys must override `validate_config/1` to verify the key is present.
  """

  @type config :: map()
  # Will be tightened to ChatContext.t() in Phase 2
  @type chat_context :: term()
  @type chat_message :: %{role: atom(), content: String.t()}
  @type error_reason :: :api_error | :timeout | :invalid_config | :rate_limited | term()

  @doc """
  Sends a chat context to the LLM and returns a single response message.

  `chat_context` is a collection of messages representing the conversation history.
  `opts` may include provider-specific options such as `model:`, `temperature:`, or `max_tokens:`.

  Returns `{:ok, chat_message}` on success or `{:error, reason}` on failure.
  """
  @callback chat(chat_context :: chat_context(), opts :: keyword()) ::
              {:ok, chat_message()} | {:error, error_reason()}

  @doc """
  Starts a streaming LLM response process.

  Returns `{:ok, stream_pid}` where `stream_pid` is the PID of a process that:

  - Sends `{:llm_chunk, %Livekit.Agents.LLM.LLMChunk{}}` messages to the
    process that called `stream/2` (captured as `self()` at invocation time).
  - Terminates normally after sending the terminal chunk (`type: :done`).
  - Sends `{:error, reason}` to the subscriber on failure.

  `chat_context` is a collection of messages representing the conversation history.
  `opts` may include provider-specific options such as `model:` or `temperature:`.
  """
  @callback stream(chat_context :: chat_context(), opts :: keyword()) ::
              {:ok, pid()} | {:error, error_reason()}

  @doc """
  Returns a map describing the provider's capabilities.

  Required keys:

  - `:streaming` — whether the provider supports `stream/2`
  - `:tool_calling` — whether the provider supports function/tool calling
  - `:vision` — whether the provider supports image inputs
  - `:max_context_tokens` — maximum context window size in tokens, or `nil` if unknown
  """
  @callback capabilities() :: %{
              streaming: boolean(),
              tool_calling: boolean(),
              vision: boolean(),
              max_context_tokens: pos_integer() | nil
            }

  @doc """
  Validates a provider configuration map.

  Returns `:ok` if the config is valid, or `{:error, reason}` otherwise.
  The default implementation (injected by `use Livekit.Agents.LLM`) returns `:ok`.
  Override this in your provider to validate required fields such as `:api_key`.
  """
  @callback validate_config(config :: config()) :: :ok | {:error, error_reason()}

  # NOTE: stream arity is 2 (chat_context + opts) — must NOT be stream: 1
  @optional_callbacks [stream: 2, validate_config: 1]

  @doc """
  Injects `@behaviour Livekit.Agents.LLM` and a default `validate_config/1`
  that returns `:ok`. Override `validate_config/1` in your provider module to
  add real validation (e.g., verifying `:api_key` is present in the config map).
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Livekit.Agents.LLM

      @impl Livekit.Agents.LLM
      def validate_config(_config), do: :ok

      defoverridable validate_config: 1
    end
  end
end

defmodule Livekit.Agents.LLM.LLMChunk do
  @moduledoc """
  A streaming chunk emitted by an LLM streaming process.

  Streaming processes send `{:llm_chunk, %LLMChunk{}}` to the subscriber
  process (the PID that called `stream/2`).

  ## Chunk types

  - `:text` — a text fragment from the LLM response; `content` is a `String.t()`
  - `:tool_call` — a tool/function call request; `content` is a map with tool call
    details (schema to be defined in Phase 3)
  - `:done` — signals stream completion; `content` is `nil`

  A `:done` chunk signals that the streaming process has finished and will exit normally.

  ## Fields

  - `:type` — one of `:text`, `:tool_call`, or `:done` (required, no default)
  - `:content` — chunk payload; `String.t()` for `:text`, a map for `:tool_call`, `nil` for `:done`
  """

  @type chunk_type :: :text | :tool_call | :done

  @type t :: %__MODULE__{
          type: chunk_type(),
          content: term()
        }

  defstruct [:type, content: nil]
end

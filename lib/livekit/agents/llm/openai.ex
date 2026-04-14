defmodule Livekit.Agents.LLM.OpenAI do
  @moduledoc """
  OpenAI Large Language Model provider for LiveKit agents.

  This module provides LLM functionality using OpenAI's API,
  supporting text generation, tool calls, and conversation management.
  """

  use GenServer
  require Logger

  defmodule Config do
    @moduledoc """
    Configuration for OpenAI LLM provider.
    """

    @type t :: %__MODULE__{
      api_key: String.t(),
      model: String.t(),
      instructions: String.t(),
      temperature: float(),
      max_tokens: pos_integer(),
      tools: list(),
      tool_choice: String.t() | nil,
      stream: boolean(),
      response_format: String.t()
    }

    defstruct [
      api_key: nil,
      model: "gpt-4o-mini",
      instructions: "You are a helpful AI assistant.",
      temperature: 0.7,
      max_tokens: 1000,
      tools: [],
      tool_choice: nil,
      stream: false,
      response_format: "text"
    ]
  end

  defmodule Message do
    @moduledoc """
    Represents a conversation message.
    """

    @type role :: :system | :user | :assistant | :tool

    @type t :: %__MODULE__{
      role: role(),
      content: String.t(),
      tool_calls: list() | nil,
      tool_call_id: String.t() | nil,
      name: String.t() | nil
    }

    defstruct [:role, :content, :tool_calls, :tool_call_id, :name]
  end

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
      config: Config.t(),
      client: Tesla.Client.t(),
      conversation_history: list(Message.t()),
      metrics: map()
    }

    defstruct [
      :config,
      :client,
      conversation_history: [],
      metrics: %{
        requests_sent: 0,
        responses_received: 0,
        tokens_used: 0,
        tool_calls_made: 0,
        errors: 0
      }
    ]
  end

  # Client API

  @doc """
  Starts the OpenAI LLM provider.
  """
  @spec start_link(Config.t()) :: GenServer.on_start()
  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  @doc """
  Processes text input and generates a response.
  """
  @spec process_text(pid(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def process_text(llm_pid, text) do
    GenServer.call(llm_pid, {:process_text, text}, 30_000)
  end

  @doc """
  Adds a message to the conversation history.
  """
  @spec add_message(pid(), Message.t()) :: :ok
  def add_message(llm_pid, message) do
    GenServer.cast(llm_pid, {:add_message, message})
  end

  @doc """
  Gets the current conversation history.
  """
  @spec get_conversation_history(pid()) :: list(Message.t())
  def get_conversation_history(llm_pid) do
    GenServer.call(llm_pid, :get_conversation_history)
  end

  @doc """
  Clears the conversation history.
  """
  @spec clear_conversation(pid()) :: :ok
  def clear_conversation(llm_pid) do
    GenServer.cast(llm_pid, :clear_conversation)
  end

  @doc """
  Updates the system instructions.
  """
  @spec update_instructions(pid(), String.t()) :: :ok
  def update_instructions(llm_pid, instructions) do
    GenServer.cast(llm_pid, {:update_instructions, instructions})
  end

  @doc """
  Gets provider metrics.
  """
  @spec get_metrics(pid()) :: map()
  def get_metrics(llm_pid) do
    GenServer.call(llm_pid, :get_metrics)
  end

  # GenServer Callbacks

  @impl true
  def init(config) do
    Logger.info("Starting OpenAI LLM provider with model: #{config.model}")

    case validate_config(config) do
      :ok ->
        client = create_http_client(config)

        # Initialize with system message
        system_message = %Message{
          role: :system,
          content: config.instructions
        }

        state = %State{
          config: config,
          client: client,
          conversation_history: [system_message]
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("Invalid OpenAI configuration: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:process_text, text}, _from, state) do
    case generate_response(state, text) do
      {:ok, response, new_state} ->
        {:reply, {:ok, response}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call(:get_conversation_history, _from, state) do
    {:reply, state.conversation_history, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  @impl true
  def handle_cast({:add_message, message}, state) do
    new_history = [message | state.conversation_history]
    new_state = %{state | conversation_history: new_history}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:clear_conversation, state) do
    # Keep only the system message
    system_message = %Message{
      role: :system,
      content: state.config.instructions
    }

    new_state = %{state | conversation_history: [system_message]}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_instructions, instructions}, state) do
    # Update the system message
    new_system_message = %Message{
      role: :system,
      content: instructions
    }

    # Replace the first (system) message in history
    new_history = case state.conversation_history do
      [%Message{role: :system} | rest] ->
        [new_system_message | rest]

      history ->
        [new_system_message | history]
    end

    new_config = %{state.config | instructions: instructions}
    new_state = %{state | config: new_config, conversation_history: new_history}

    {:noreply, new_state}
  end

  # Private Functions

  defp validate_config(config) do
    cond do
      is_nil(config.api_key) or config.api_key == "" ->
        {:error, :missing_api_key}

      config.temperature < 0 or config.temperature > 2 ->
        {:error, :invalid_temperature}

      config.max_tokens <= 0 ->
        {:error, :invalid_max_tokens}

      true ->
        :ok
    end
  end

  defp create_http_client(config) do
    middleware = [
      {Tesla.Middleware.BaseUrl, "https://api.openai.com/v1"},
      {Tesla.Middleware.Headers, [
        {"Authorization", "Bearer #{config.api_key}"},
        {"Content-Type", "application/json"}
      ]},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Logger, debug: false}
    ]

    Tesla.client(middleware, Tesla.Adapter.Hackney)
  end

  defp generate_response(state, user_text) do
    try do
      # Add user message to history
      user_message = %Message{role: :user, content: user_text}
      messages_for_api = build_messages_for_api([user_message | state.conversation_history])

      # For development, use mock response
      response_text = mock_llm_response(user_text)

      # Add messages to conversation history
      assistant_message = %Message{role: :assistant, content: response_text}
      new_history = [assistant_message, user_message | state.conversation_history]

      # Update metrics
      new_metrics = state.metrics
                   |> Map.update!(:requests_sent, &(&1 + 1))
                   |> Map.update!(:responses_received, &(&1 + 1))
                   |> Map.update!(:tokens_used, &(&1 + estimate_tokens(user_text) + estimate_tokens(response_text)))

      new_state = %{state |
        conversation_history: new_history,
        metrics: new_metrics
      }

      {:ok, response_text, new_state}
    rescue
      error ->
        Logger.error("OpenAI LLM error: #{inspect(error)}")
        error_metrics = Map.update!(state.metrics, :errors, &(&1 + 1))
        new_state = %{state | metrics: error_metrics}
        {:error, error, new_state}
    end
  end

  defp build_messages_for_api(messages) do
    # Convert internal message format to OpenAI API format
    messages
    |> Enum.reverse()  # API expects chronological order
    |> Enum.map(fn message ->
      base_message = %{
        role: Atom.to_string(message.role),
        content: message.content
      }

      # Add optional fields if present
      base_message
      |> maybe_add_field(:tool_calls, message.tool_calls)
      |> maybe_add_field(:tool_call_id, message.tool_call_id)
      |> maybe_add_field(:name, message.name)
    end)
  end

  defp maybe_add_field(map, _key, nil), do: map
  defp maybe_add_field(map, key, value), do: Map.put(map, key, value)

  defp build_api_request_body(state, messages) do
    base_body = %{
      model: state.config.model,
      messages: messages,
      temperature: state.config.temperature,
      max_tokens: state.config.max_tokens
    }

    # Add optional fields
    base_body
    |> maybe_add_field(:tools, format_tools(state.config.tools))
    |> maybe_add_field(:tool_choice, state.config.tool_choice)
    |> maybe_add_field(:stream, state.config.stream)
  end

  defp format_tools([]), do: nil
  defp format_tools(tools) do
    Enum.map(tools, fn tool ->
      %{
        type: "function",
        function: tool
      }
    end)
  end

  defp estimate_tokens(text) do
    # Rough estimation: ~4 characters per token
    div(String.length(text), 4)
  end

  # Mock function for development
  defp mock_llm_response(user_text) do
    # Simple mock responses based on input
    user_text_lower = String.downcase(user_text)

    cond do
      String.contains?(user_text_lower, ["hello", "hi"]) ->
        "Hello! How can I help you today?"

      String.contains?(user_text_lower, ["weather"]) ->
        "I'd be happy to help with weather information, but I don't have access to current weather data. You might want to check a weather app or website for the most up-to-date information."

      String.contains?(user_text_lower, ["time"]) ->
        "I don't have access to the current time, but you can check your device's clock or ask about a specific timezone."

      String.contains?(user_text_lower, ["how are you", "how do you feel"]) ->
        "I'm doing well, thank you for asking! I'm here and ready to help with whatever you need."

      String.contains?(user_text_lower, ["thank you", "thanks"]) ->
        "You're welcome! Is there anything else I can help you with?"

      String.contains?(user_text_lower, ["goodbye", "bye"]) ->
        "Goodbye! Have a great day!"

      String.length(user_text) < 10 ->
        "I understand. Could you tell me more about what you'd like to know or discuss?"

      true ->
        "That's interesting! I appreciate you sharing that with me. How can I assist you further with this topic?"
    end
  end
end
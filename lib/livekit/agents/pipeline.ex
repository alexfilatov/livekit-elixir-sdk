defmodule Livekit.Agents.Pipeline do
  @moduledoc """
  Voice processing pipeline that orchestrates STT, LLM, and TTS components.

  The pipeline handles the flow of audio and text data through various
  processing stages to create a complete voice AI experience.
  """

  require Logger
  alias Livekit.Agents.AudioFrame

  defmodule Node do
    @moduledoc """
    Represents a processing node in the pipeline.
    """

    @type node_type :: :stt | :llm | :tts | :vad

    @type t :: %__MODULE__{
      type: node_type(),
      module: module(),
      config: map(),
      state: term(),
      pid: pid() | nil
    }

    defstruct [:type, :module, :config, :state, :pid]
  end

  @type t :: %__MODULE__{
    nodes: list(Node.t()),
    state: :idle | :processing | :error,
    buffer: list(),
    metrics: map()
  }

  defstruct [
    nodes: [],
    state: :idle,
    buffer: [],
    metrics: %{
      total_processed: 0,
      processing_time_ms: 0,
      errors: 0
    }
  ]

  @doc """
  Creates a new empty pipeline.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Adds an STT (Speech-to-Text) node to the pipeline.
  """
  @spec add_stt_node(t(), module(), map()) :: t()
  def add_stt_node(pipeline, stt_module, config) do
    Logger.debug("Adding STT node: #{inspect(stt_module)}")

    case initialize_node(:stt, stt_module, config) do
      {:ok, node} ->
        %{pipeline | nodes: [node | pipeline.nodes]}

      {:error, reason} ->
        Logger.error("Failed to initialize STT node: #{inspect(reason)}")
        pipeline
    end
  end

  @doc """
  Adds an LLM (Large Language Model) node to the pipeline.
  """
  @spec add_llm_node(t(), module(), map()) :: t()
  def add_llm_node(pipeline, llm_module, config) do
    Logger.debug("Adding LLM node: #{inspect(llm_module)}")

    case initialize_node(:llm, llm_module, config) do
      {:ok, node} ->
        %{pipeline | nodes: [node | pipeline.nodes]}

      {:error, reason} ->
        Logger.error("Failed to initialize LLM node: #{inspect(reason)}")
        pipeline
    end
  end

  @doc """
  Adds a TTS (Text-to-Speech) node to the pipeline.
  """
  @spec add_tts_node(t(), module(), map()) :: t()
  def add_tts_node(pipeline, tts_module, config) do
    Logger.debug("Adding TTS node: #{inspect(tts_module)}")

    case initialize_node(:tts, tts_module, config) do
      {:ok, node} ->
        %{pipeline | nodes: [node | pipeline.nodes]}

      {:error, reason} ->
        Logger.error("Failed to initialize TTS node: #{inspect(reason)}")
        pipeline
    end
  end

  @doc """
  Processes audio data through the pipeline.
  """
  @spec process_audio(t(), AudioFrame.t()) :: {:ok, term()} | {:error, term()}
  def process_audio(pipeline, audio_frame) do
    start_time = System.monotonic_time(:millisecond)

    try do
      case find_node_by_type(pipeline, :stt) do
        nil ->
          {:error, :no_stt_node}

        stt_node ->
          case process_through_stt(stt_node, audio_frame) do
            {:ok, {:text, text}} ->
              # Continue through LLM if available
              process_text_through_pipeline(pipeline, text, start_time)

            {:ok, {:partial, _text}} ->
              # Partial transcription, continue collecting
              {:ok, :processing}

            {:ok, :silence} ->
              # No speech detected
              {:ok, :silence}

            {:error, reason} ->
              {:error, reason}
          end
      end
    rescue
      error ->
        Logger.error("Pipeline processing error: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Processes text through the LLM and TTS stages of the pipeline.
  """
  @spec process_text(t(), String.t()) :: {:ok, term()} | {:error, term()}
  def process_text(pipeline, text) do
    start_time = System.monotonic_time(:millisecond)
    process_text_through_pipeline(pipeline, text, start_time)
  end

  @doc """
  Cleans up pipeline resources.
  """
  @spec cleanup(t()) :: :ok
  def cleanup(pipeline) do
    Logger.debug("Cleaning up pipeline with #{length(pipeline.nodes)} nodes")

    Enum.each(pipeline.nodes, fn node ->
      if node.pid do
        GenServer.stop(node.pid, :normal, 5000)
      end
    end)

    :ok
  end

  @doc """
  Gets pipeline statistics and metrics.
  """
  @spec get_metrics(t()) :: map()
  def get_metrics(pipeline) do
    node_status = Enum.map(pipeline.nodes, fn node ->
      %{
        type: node.type,
        module: node.module,
        status: if(node.pid && Process.alive?(node.pid), do: :alive, else: :dead)
      }
    end)

    Map.merge(pipeline.metrics, %{
      state: pipeline.state,
      nodes: node_status,
      buffer_size: length(pipeline.buffer)
    })
  end

  # Private Functions

  defp initialize_node(type, module, config) do
    try do
      case apply(module, :start_link, [config]) do
        {:ok, pid} ->
          node = %Node{
            type: type,
            module: module,
            config: config,
            pid: pid,
            state: :ready
          }
          {:ok, node}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Node initialization error: #{inspect(error)}")
        # For now, create a mock node to allow development to continue
        node = %Node{
          type: type,
          module: module,
          config: config,
          pid: nil,
          state: :mock
        }
        {:ok, node}
    end
  end

  defp find_node_by_type(pipeline, type) do
    Enum.find(pipeline.nodes, fn node -> node.type == type end)
  end

  defp process_through_stt(stt_node, audio_frame) do
    if stt_node.pid && Process.alive?(stt_node.pid) do
      try do
        GenServer.call(stt_node.pid, {:process_audio, audio_frame}, 5000)
      catch
        :exit, {:timeout, _} ->
          {:error, :stt_timeout}
        :exit, reason ->
          {:error, {:stt_process_error, reason}}
      end
    else
      # Mock STT for development
      mock_stt_process(audio_frame)
    end
  end

  defp process_text_through_pipeline(pipeline, text, start_time) do
    with {:ok, llm_response} <- process_through_llm(pipeline, text),
         {:ok, audio_data} <- process_through_tts(pipeline, llm_response) do

      end_time = System.monotonic_time(:millisecond)
      processing_time = end_time - start_time

      Logger.debug("Pipeline processing completed in #{processing_time}ms")

      {:ok, {:complete, %{
        original_text: text,
        llm_response: llm_response,
        audio_data: audio_data,
        processing_time_ms: processing_time
      }}}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_through_llm(pipeline, text) do
    case find_node_by_type(pipeline, :llm) do
      nil ->
        Logger.warn("No LLM node available, skipping LLM processing")
        {:ok, text}

      llm_node ->
        if llm_node.pid && Process.alive?(llm_node.pid) do
          try do
            GenServer.call(llm_node.pid, {:process_text, text}, 10000)
          catch
            :exit, {:timeout, _} ->
              {:error, :llm_timeout}
            :exit, reason ->
              {:error, {:llm_process_error, reason}}
          end
        else
          # Mock LLM for development
          mock_llm_process(text)
        end
    end
  end

  defp process_through_tts(pipeline, text) do
    case find_node_by_type(pipeline, :tts) do
      nil ->
        Logger.warn("No TTS node available, skipping TTS processing")
        {:ok, nil}

      tts_node ->
        if tts_node.pid && Process.alive?(tts_node.pid) do
          try do
            GenServer.call(tts_node.pid, {:synthesize_text, text}, 10000)
          catch
            :exit, {:timeout, _} ->
              {:error, :tts_timeout}
            :exit, reason ->
              {:error, {:tts_process_error, reason}}
          end
        else
          # Mock TTS for development
          mock_tts_process(text)
        end
    end
  end

  # Mock implementations for development
  defp mock_stt_process(audio_frame) do
    # Simulate STT processing
    if byte_size(audio_frame.data) > 1000 do
      {:ok, {:text, "Hello, this is a mock transcription of the audio input."}}
    else
      {:ok, :silence}
    end
  end

  defp mock_llm_process(text) do
    # Simulate LLM processing
    response = "I understand you said: '#{text}'. How can I help you further?"
    {:ok, response}
  end

  defp mock_tts_process(text) do
    # Simulate TTS processing - return mock audio data
    audio_size = String.length(text) * 100  # Rough estimation
    mock_audio = :crypto.strong_rand_bytes(audio_size)
    {:ok, mock_audio}
  end
end
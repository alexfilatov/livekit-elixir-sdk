defmodule Livekit.Agents.VoiceAgent do
  @moduledoc """
  Voice agent implementation for LiveKit with STT, LLM, and TTS pipeline.

  This module provides a complete voice processing pipeline that can:
  - Convert speech to text using configurable STT providers
  - Process text through language models with tool support
  - Convert responses back to speech using TTS providers
  - Handle voice activity detection and turn management

  ## Example

      config = %Livekit.Agents.VoiceAgent.Config{
        stt: {Livekit.Agents.STT.Deepgram, %{api_key: "your_key"}},
        llm: {Livekit.Agents.LLM.OpenAI, %{api_key: "your_key", model: "gpt-4o-mini"}},
        tts: {Livekit.Agents.TTS.OpenAI, %{api_key: "your_key", voice: "ash"}},
        instructions: "You are a helpful assistant named Kelly."
      }

      {:ok, agent} = Livekit.Agents.VoiceAgent.start_link(config)
  """

  use GenServer
  require Logger

  alias Livekit.Agents.{Pipeline, AudioFrame, VoiceAgent}

  defmodule Config do
    @moduledoc """
    Configuration for VoiceAgent.
    """

    @type stt_provider :: {module(), map()}
    @type llm_provider :: {module(), map()}
    @type tts_provider :: {module(), map()}

    @type t :: %__MODULE__{
            stt: stt_provider(),
            llm: llm_provider(),
            tts: tts_provider(),
            instructions: String.t(),
            name: String.t(),
            vad_enabled: boolean(),
            turn_detection: :multilingual | :simple,
            preemptive_synthesis: boolean(),
            tools: list(),
            metadata: map()
          }

    defstruct [
      :stt,
      :llm,
      :tts,
      instructions: "You are a helpful AI assistant.",
      name: "Assistant",
      vad_enabled: true,
      turn_detection: :multilingual,
      preemptive_synthesis: true,
      tools: [],
      metadata: %{}
    ]
  end

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            config: VoiceAgent.Config.t(),
            pipeline: Pipeline.t() | nil,
            session: pid() | nil,
            room: pid() | nil,
            conversation_context: list(),
            current_turn: map() | nil,
            metrics: map()
          }

    defstruct [
      :config,
      :pipeline,
      :session,
      :room,
      conversation_context: [],
      current_turn: nil,
      metrics: %{
        turns_processed: 0,
        audio_frames_processed: 0,
        errors: 0,
        last_activity: nil
      }
    ]
  end

  # Client API

  @doc """
  Starts a VoiceAgent with the given configuration.
  """
  @spec start_link(VoiceAgent.Config.t(), GenServer.options()) :: GenServer.on_start()
  def start_link(config, opts \\ []) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  @doc """
  Connects the agent to a room session.
  """
  @spec connect_to_session(pid(), pid()) :: :ok | {:error, term()}
  def connect_to_session(agent_pid, session_pid) do
    GenServer.call(agent_pid, {:connect_to_session, session_pid})
  end

  @doc """
  Processes an incoming audio frame through the voice pipeline.
  """
  @spec process_audio_frame(pid(), AudioFrame.t()) :: :ok | {:error, term()}
  def process_audio_frame(agent_pid, audio_frame) do
    GenServer.cast(agent_pid, {:process_audio_frame, audio_frame})
  end

  @doc """
  Gets the current conversation context.
  """
  @spec get_conversation_context(pid()) :: list()
  def get_conversation_context(agent_pid) do
    GenServer.call(agent_pid, :get_conversation_context)
  end

  @doc """
  Gets agent metrics and statistics.
  """
  @spec get_metrics(pid()) :: map()
  def get_metrics(agent_pid) do
    GenServer.call(agent_pid, :get_metrics)
  end

  @doc """
  Updates agent configuration at runtime.
  """
  @spec update_config(pid(), map()) :: :ok | {:error, term()}
  def update_config(agent_pid, config_updates) do
    GenServer.call(agent_pid, {:update_config, config_updates})
  end

  # GenServer Callbacks

  @impl true
  def init(config) do
    Logger.info("Initializing VoiceAgent with name: #{config.name}")

    case initialize_pipeline(config) do
      {:ok, pipeline} ->
        state = %State{
          config: config,
          pipeline: pipeline,
          metrics: %{
            turns_processed: 0,
            audio_frames_processed: 0,
            errors: 0,
            last_activity: nil,
            initialized_at: DateTime.utc_now()
          }
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to initialize VoiceAgent pipeline: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:connect_to_session, session_pid}, _from, state) do
    Logger.info("VoiceAgent connecting to session: #{inspect(session_pid)}")

    # Monitor the session process
    Process.monitor(session_pid)

    new_state = %{state | session: session_pid}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_conversation_context, _from, state) do
    {:reply, state.conversation_context, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    current_metrics = Map.put(state.metrics, :last_checked, DateTime.utc_now())
    {:reply, current_metrics, state}
  end

  @impl true
  def handle_call({:update_config, config_updates}, _from, state) do
    case update_agent_config(state.config, config_updates) do
      {:ok, new_config} ->
        case reinitialize_pipeline_if_needed(state.pipeline, state.config, new_config) do
          {:ok, new_pipeline} ->
            new_state = %{state | config: new_config, pipeline: new_pipeline}
            {:reply, :ok, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:process_audio_frame, audio_frame}, state) do
    new_state = process_audio_frame_internal(audio_frame, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    if pid == state.session do
      Logger.warning("Agent session #{inspect(pid)} went down: #{inspect(reason)}")
      new_state = %{state | session: nil}
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("VoiceAgent received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("VoiceAgent terminating: #{inspect(reason)}")
    cleanup_pipeline(state.pipeline)
    :ok
  end

  # Private Functions

  defp initialize_pipeline(config) do
    try do
      pipeline = Pipeline.new()

      # Initialize STT component
      pipeline =
        case config.stt do
          {stt_module, stt_config} ->
            Pipeline.add_stt_node(pipeline, stt_module, stt_config)

          nil ->
            pipeline
        end

      # Initialize LLM component
      pipeline =
        case config.llm do
          {llm_module, llm_config} ->
            llm_config_with_instructions = Map.put(llm_config, :instructions, config.instructions)
            Pipeline.add_llm_node(pipeline, llm_module, llm_config_with_instructions)

          nil ->
            pipeline
        end

      # Initialize TTS component
      pipeline =
        case config.tts do
          {tts_module, tts_config} ->
            Pipeline.add_tts_node(pipeline, tts_module, tts_config)

          nil ->
            pipeline
        end

      {:ok, pipeline}
    rescue
      error ->
        {:error, error}
    end
  end

  defp process_audio_frame_internal(audio_frame, state) do
    try do
      # Update metrics
      new_metrics = Map.update!(state.metrics, :audio_frames_processed, &(&1 + 1))
      new_metrics = Map.put(new_metrics, :last_activity, DateTime.utc_now())

      # Process through pipeline
      case Pipeline.process_audio(state.pipeline, audio_frame) do
        {:ok, result} ->
          handle_pipeline_result(result, %{state | metrics: new_metrics})

        {:error, reason} ->
          Logger.error("Pipeline processing failed: #{inspect(reason)}")
          error_metrics = Map.update!(new_metrics, :errors, &(&1 + 1))
          %{state | metrics: error_metrics}
      end
    rescue
      error ->
        Logger.error("Audio frame processing error: #{inspect(error)}")
        error_metrics = Map.update!(state.metrics, :errors, &(&1 + 1))
        %{state | metrics: error_metrics}
    end
  end

  defp handle_pipeline_result(result, state) do
    case result do
      {:text_transcribed, text} ->
        Logger.debug("Transcribed text: #{text}")
        # Add to conversation context
        context_entry = %{type: :user, content: text, timestamp: DateTime.utc_now()}
        new_context = [context_entry | state.conversation_context]
        %{state | conversation_context: new_context}

      {:llm_response, response} ->
        Logger.debug("LLM response: #{inspect(response)}")
        # Add to conversation context
        context_entry = %{type: :assistant, content: response, timestamp: DateTime.utc_now()}
        new_context = [context_entry | state.conversation_context]

        # Update turn metrics
        new_metrics = Map.update!(state.metrics, :turns_processed, &(&1 + 1))

        %{state | conversation_context: new_context, metrics: new_metrics}

      {:audio_synthesized, audio_data} ->
        Logger.debug("Audio synthesized, #{byte_size(audio_data)} bytes")
        # Send audio to session if connected
        if state.session do
          send_audio_to_session(state.session, audio_data)
        end

        state

      {:error, reason} ->
        Logger.error("Pipeline result error: #{inspect(reason)}")
        error_metrics = Map.update!(state.metrics, :errors, &(&1 + 1))
        %{state | metrics: error_metrics}

      _ ->
        Logger.debug("Unknown pipeline result: #{inspect(result)}")
        state
    end
  end

  defp send_audio_to_session(session_pid, audio_data) do
    # This will be implemented when we have the session module
    # For now, just log
    Logger.debug(
      "Would send #{byte_size(audio_data)} bytes of audio to session #{inspect(session_pid)}"
    )
  end

  defp update_agent_config(current_config, updates) do
    try do
      new_config = struct(current_config, updates)
      {:ok, new_config}
    rescue
      error ->
        {:error, error}
    end
  end

  defp reinitialize_pipeline_if_needed(current_pipeline, old_config, new_config) do
    # Check if any pipeline components changed
    if pipeline_config_changed?(old_config, new_config) do
      cleanup_pipeline(current_pipeline)
      initialize_pipeline(new_config)
    else
      {:ok, current_pipeline}
    end
  end

  defp pipeline_config_changed?(old_config, new_config) do
    old_config.stt != new_config.stt or
      old_config.llm != new_config.llm or
      old_config.tts != new_config.tts or
      old_config.instructions != new_config.instructions
  end

  defp cleanup_pipeline(nil), do: :ok

  defp cleanup_pipeline(pipeline) do
    # Clean up pipeline resources
    Pipeline.cleanup(pipeline)
  end
end

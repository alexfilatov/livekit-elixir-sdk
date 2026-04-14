defmodule Livekit.Agents.STT.Deepgram do
  @moduledoc """
  Deepgram Speech-to-Text provider for LiveKit agents.

  This module provides speech-to-text functionality using Deepgram's API.
  It supports both streaming and non-streaming transcription.
  """

  use GenServer
  require Logger

  alias Livekit.Agents.AudioFrame

  defmodule Config do
    @moduledoc """
    Configuration for Deepgram STT provider.
    """

    @type t :: %__MODULE__{
      api_key: String.t(),
      model: String.t(),
      language: String.t(),
      smart_format: boolean(),
      punctuate: boolean(),
      diarize: boolean(),
      interim_results: boolean(),
      endpointing: boolean(),
      vad_events: boolean(),
      sample_rate: pos_integer(),
      encoding: String.t()
    }

    defstruct [
      api_key: nil,
      model: "nova-2",
      language: "en-US",
      smart_format: true,
      punctuate: true,
      diarize: false,
      interim_results: true,
      endpointing: true,
      vad_events: true,
      sample_rate: 48_000,
      encoding: "linear16"
    ]
  end

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
      config: Config.t(),
      client: Tesla.Client.t(),
      websocket: pid() | nil,
      streaming: boolean(),
      buffer: binary(),
      last_transcript: String.t(),
      metrics: map()
    }

    defstruct [
      :config,
      :client,
      :websocket,
      streaming: false,
      buffer: <<>>,
      last_transcript: "",
      metrics: %{
        requests_sent: 0,
        responses_received: 0,
        total_audio_duration_ms: 0,
        errors: 0
      }
    ]
  end

  # Client API

  @doc """
  Starts the Deepgram STT provider.
  """
  @spec start_link(Config.t()) :: GenServer.on_start()
  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  @doc """
  Processes audio through speech-to-text.
  """
  @spec process_audio(pid(), AudioFrame.t()) :: {:ok, term()} | {:error, term()}
  def process_audio(stt_pid, audio_frame) do
    GenServer.call(stt_pid, {:process_audio, audio_frame}, 10_000)
  end

  @doc """
  Transcribes audio data directly (non-streaming).
  """
  @spec transcribe(pid(), binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def transcribe(stt_pid, audio_data, opts \\ []) do
    GenServer.call(stt_pid, {:transcribe, audio_data, opts}, 15_000)
  end

  @doc """
  Starts streaming transcription.
  """
  @spec start_streaming(pid()) :: :ok | {:error, term()}
  def start_streaming(stt_pid) do
    GenServer.call(stt_pid, :start_streaming)
  end

  @doc """
  Stops streaming transcription.
  """
  @spec stop_streaming(pid()) :: :ok
  def stop_streaming(stt_pid) do
    GenServer.call(stt_pid, :stop_streaming)
  end

  @doc """
  Gets provider metrics.
  """
  @spec get_metrics(pid()) :: map()
  def get_metrics(stt_pid) do
    GenServer.call(stt_pid, :get_metrics)
  end

  # GenServer Callbacks

  @impl true
  def init(config) do
    Logger.info("Starting Deepgram STT provider")

    # Validate configuration
    case validate_config(config) do
      :ok ->
        client = create_http_client(config)

        state = %State{
          config: config,
          client: client
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("Invalid Deepgram configuration: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:process_audio, audio_frame}, _from, state) do
    case process_audio_frame(state, audio_frame) do
      {:ok, result, new_state} ->
        {:reply, {:ok, result}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call({:transcribe, audio_data, opts}, _from, state) do
    case transcribe_audio(state, audio_data, opts) do
      {:ok, transcript, new_state} ->
        {:reply, {:ok, transcript}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call(:start_streaming, _from, state) do
    case start_websocket_streaming(state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:stop_streaming, _from, state) do
    new_state = stop_websocket_streaming(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  @impl true
  def handle_info({:websocket_message, message}, state) do
    new_state = handle_websocket_message(state, message)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:websocket_closed, reason}, state) do
    Logger.warn("Deepgram WebSocket closed: #{inspect(reason)}")
    new_state = %{state | websocket: nil, streaming: false}
    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, state) do
    stop_websocket_streaming(state)
    :ok
  end

  # Private Functions

  defp validate_config(config) do
    cond do
      is_nil(config.api_key) or config.api_key == "" ->
        {:error, :missing_api_key}

      config.sample_rate <= 0 ->
        {:error, :invalid_sample_rate}

      true ->
        :ok
    end
  end

  defp create_http_client(config) do
    middleware = [
      {Tesla.Middleware.BaseUrl, "https://api.deepgram.com/v1"},
      {Tesla.Middleware.Headers, [
        {"Authorization", "Token #{config.api_key}"},
        {"Content-Type", "application/json"}
      ]},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Logger, debug: false}
    ]

    Tesla.client(middleware, Tesla.Adapter.Hackney)
  end

  defp process_audio_frame(state, audio_frame) do
    if state.streaming do
      # Send to WebSocket
      send_audio_to_websocket(state, audio_frame)
    else
      # Buffer for batch processing
      new_buffer = state.buffer <> audio_frame.data
      buffer_duration_ms = calculate_buffer_duration(new_buffer, audio_frame.sample_rate)

      # Process if buffer is large enough (e.g., 1 second)
      if buffer_duration_ms >= 1000 do
        case transcribe_audio(state, new_buffer, []) do
          {:ok, transcript, new_state} ->
            result = if String.trim(transcript) != "" do
              {:text, transcript}
            else
              :silence
            end

            clean_state = %{new_state | buffer: <<>>}
            {:ok, result, clean_state}

          {:error, reason, new_state} ->
            {:error, reason, new_state}
        end
      else
        new_state = %{state | buffer: new_buffer}
        {:ok, :processing, new_state}
      end
    end
  end

  defp transcribe_audio(state, audio_data, _opts) do
    try do
      # Prepare request body
      body = %{
        model: state.config.model,
        language: state.config.language,
        smart_format: state.config.smart_format,
        punctuate: state.config.punctuate,
        diarize: state.config.diarize,
        encoding: state.config.encoding,
        sample_rate: state.config.sample_rate
      }

      # For development, use mock transcription
      transcript = mock_transcribe(audio_data)

      new_metrics = state.metrics
                   |> Map.update!(:requests_sent, &(&1 + 1))
                   |> Map.update!(:responses_received, &(&1 + 1))

      new_state = %{state |
        last_transcript: transcript,
        metrics: new_metrics
      }

      {:ok, transcript, new_state}
    rescue
      error ->
        Logger.error("Deepgram transcription error: #{inspect(error)}")
        error_metrics = Map.update!(state.metrics, :errors, &(&1 + 1))
        new_state = %{state | metrics: error_metrics}
        {:error, error, new_state}
    end
  end

  defp start_websocket_streaming(state) do
    # For development, simulate WebSocket streaming
    Logger.info("Starting Deepgram WebSocket streaming (mock)")

    new_state = %{state | streaming: true, websocket: :mock_websocket}
    {:ok, new_state}
  end

  defp stop_websocket_streaming(state) do
    if state.websocket do
      Logger.info("Stopping Deepgram WebSocket streaming")
    end

    %{state | streaming: false, websocket: nil}
  end

  defp send_audio_to_websocket(state, audio_frame) do
    if state.websocket do
      Logger.debug("Sending audio to Deepgram WebSocket: #{byte_size(audio_frame.data)} bytes")

      # Simulate processing delay and response
      spawn(fn ->
        Process.sleep(100)
        transcript = mock_transcribe(audio_frame.data)
        if String.trim(transcript) != "" do
          send(self(), {:websocket_message, %{transcript: transcript, is_final: false}})
        end
      end)

      new_metrics = Map.update!(state.metrics, :requests_sent, &(&1 + 1))
      {:ok, :sent, %{state | metrics: new_metrics}}
    else
      {:error, :not_streaming, state}
    end
  end

  defp handle_websocket_message(state, message) do
    transcript = Map.get(message, :transcript, "")
    is_final = Map.get(message, :is_final, false)

    Logger.debug("Received Deepgram transcript: #{transcript} (final: #{is_final})")

    if is_final do
      # Send final transcript to parent process
      send(self(), {:transcript_result, {:text, transcript}})
    else
      # Send partial transcript
      send(self(), {:transcript_result, {:partial, transcript}})
    end

    new_metrics = Map.update!(state.metrics, :responses_received, &(&1 + 1))
    %{state | last_transcript: transcript, metrics: new_metrics}
  end

  defp calculate_buffer_duration(buffer, sample_rate) do
    # Assuming 16-bit PCM (2 bytes per sample)
    sample_count = div(byte_size(buffer), 2)
    (sample_count * 1000) / sample_rate
  end

  # Mock function for development
  defp mock_transcribe(audio_data) do
    # Simple mock that varies based on audio data size
    case byte_size(audio_data) do
      size when size < 1000 -> ""
      size when size < 5000 -> "Hello"
      size when size < 10_000 -> "Hello, how are you?"
      _ -> "Hello, how are you doing today? This is a mock transcription."
    end
  end
end
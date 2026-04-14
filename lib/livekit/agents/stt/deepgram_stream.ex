defmodule Livekit.Agents.STT.DeepgramStream do
  @moduledoc """
  GenServer managing a single Deepgram streaming WebSocket session.

  Started by `Livekit.Agents.STT.Deepgram.stream/1`. Connects to
  `wss://api.deepgram.com/v1/listen` via Gun, forwards audio frames from
  callers via `send_audio/2`, and emits `{:speech_event, %SpeechEvent{}}`
  messages to the subscriber process.

  ## Message protocol (sent to subscriber)

    - `{:speech_event, %SpeechEvent{type: :start}}` — connection established
    - `{:speech_event, %SpeechEvent{type: :interim, text: t, confidence: c}}` — partial result
    - `{:speech_event, %SpeechEvent{type: :final, text: t, confidence: c}}` — utterance complete
    - `{:speech_event, %SpeechEvent{type: :end}}` — stream closed, process exits normally
    - `{:error, reason}` — unrecoverable error

  ## Sending audio

      DeepgramStream.send_audio(stream_pid, audio_binary)

  ## Closing gracefully

      DeepgramStream.finish(stream_pid)
  """

  use GenServer
  require Logger

  alias Livekit.Agents.STT.AudioBuffer
  alias Livekit.Agents.STT.Deepgram.Config
  alias Livekit.Agents.STT.SpeechEvent

  @deepgram_host ~c"api.deepgram.com"
  @deepgram_port 443

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            config: Config.t(),
            subscriber: pid(),
            conn: pid() | nil,
            stream_ref: reference() | nil,
            buffer: AudioBuffer.t() | nil,
            connected: boolean()
          }

    defstruct [
      :config,
      :subscriber,
      conn: nil,
      stream_ref: nil,
      buffer: nil,
      connected: false
    ]
  end

  # --- Client API ---

  @doc """
  Starts a streaming session. `config` is a `Livekit.Agents.STT.Deepgram.Config` struct.
  The subscriber (caller's `self()`) receives `{:speech_event, %SpeechEvent{}}` messages.
  """
  @spec start_link({Config.t(), pid()}) :: GenServer.on_start()
  def start_link({config, subscriber}) do
    GenServer.start_link(__MODULE__, {config, subscriber})
  end

  @doc """
  Sends raw audio bytes to the streaming session. Audio is buffered until
  `min_buffer_duration_ms` is accumulated, then flushed to Deepgram.
  """
  @spec send_audio(pid(), binary()) :: :ok
  def send_audio(stream_pid, audio) when is_binary(audio) do
    GenServer.cast(stream_pid, {:send_audio, audio})
  end

  @doc """
  Sends a CloseStream message to Deepgram and initiates graceful shutdown.
  The stream process will send `{:speech_event, %SpeechEvent{type: :end}}` then exit.
  """
  @spec finish(pid()) :: :ok
  def finish(stream_pid) do
    GenServer.cast(stream_pid, :finish)
  end

  # --- GenServer callbacks ---

  @impl true
  def init({%Config{mock: true} = config, subscriber}) do
    # Mock mode: spawn a task that emits synthetic events, then schedule exit
    spawn_mock_stream(subscriber, config)
    {:ok, %State{config: config, subscriber: subscriber}}
  end

  def init({config, subscriber}) do
    buffer = AudioBuffer.new(min_duration_ms: config.min_buffer_duration_ms)
    state = %State{config: config, subscriber: subscriber, buffer: buffer}

    # Connect asynchronously so init doesn't block
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    path = build_ws_path(state.config)

    case :gun.open(@deepgram_host, @deepgram_port, %{transport: :tls}) do
      {:ok, conn} ->
        case :gun.await_up(conn, 5_000) do
          {:ok, _protocol} ->
            headers = build_ws_headers(state.config)
            stream_ref = :gun.ws_upgrade(conn, path, headers)
            {:noreply, %{state | conn: conn, stream_ref: stream_ref}}

          {:error, reason} ->
            Logger.error("Deepgram Gun connection failed: #{inspect(reason)}")
            send(state.subscriber, {:error, reason})
            {:stop, :normal, state}
        end

      {:error, reason} ->
        Logger.error("Deepgram Gun open failed: #{inspect(reason)}")
        send(state.subscriber, {:error, reason})
        {:stop, :normal, state}
    end
  end

  def handle_info({:gun_upgrade, conn, _stream_ref, ["websocket"], _headers}, state)
      when conn == state.conn do
    Logger.debug("Deepgram WebSocket connected")
    send(state.subscriber, {:speech_event, %SpeechEvent{type: :start}})
    {:noreply, %{state | connected: true}}
  end

  def handle_info({:gun_ws, conn, _stream_ref, {:text, frame}}, state)
      when conn == state.conn do
    new_state = handle_deepgram_frame(state, frame)
    {:noreply, new_state}
  end

  def handle_info({:gun_ws, conn, _stream_ref, {:close, _code, _reason}}, state)
      when conn == state.conn do
    send(state.subscriber, {:speech_event, %SpeechEvent{type: :end}})
    {:stop, :normal, state}
  end

  def handle_info({:gun_down, conn, _protocol, reason, _killed_streams}, state)
      when conn == state.conn do
    Logger.warning("Deepgram WebSocket connection lost: #{inspect(reason)}")
    send(state.subscriber, {:error, {:connection_lost, reason}})
    {:stop, :normal, state}
  end

  def handle_info(:mock_exit, state) do
    {:stop, :normal, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast({:send_audio, _audio}, %State{buffer: nil} = state) do
    # Mock mode — no buffer; audio is discarded
    {:noreply, state}
  end

  def handle_cast({:send_audio, audio}, %State{connected: false} = state) do
    # Not yet connected — buffer and wait
    new_buffer = AudioBuffer.push(state.buffer, audio, state.config.sample_rate)
    {:noreply, %{state | buffer: new_buffer}}
  end

  def handle_cast({:send_audio, audio}, state) do
    new_buffer = AudioBuffer.push(state.buffer, audio, state.config.sample_rate)

    case AudioBuffer.flush_if_ready(new_buffer) do
      {:ready, data, flushed_buffer} ->
        :gun.ws_send(state.conn, state.stream_ref, {:binary, data})
        {:noreply, %{state | buffer: flushed_buffer}}

      {:buffering, updated_buffer} ->
        {:noreply, %{state | buffer: updated_buffer}}
    end
  end

  def handle_cast(:finish, state) do
    # Flush any remaining buffered audio before closing
    remaining =
      if state.buffer do
        {data, _} = AudioBuffer.flush(state.buffer)
        data
      else
        <<>>
      end

    if byte_size(remaining) > 0 and state.connected do
      :gun.ws_send(state.conn, state.stream_ref, {:binary, remaining})
    end

    if state.connected do
      close_msg = Jason.encode!(%{"type" => "CloseStream"})
      :gun.ws_send(state.conn, state.stream_ref, {:text, close_msg})
    else
      # Never connected — emit terminal event directly
      send(state.subscriber, {:speech_event, %SpeechEvent{type: :end}})
    end

    {:noreply, state}
  end

  def handle_cast(:mock_done, state) do
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, %State{conn: conn}) when not is_nil(conn) do
    :gun.close(conn)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  # --- Private Helpers ---

  @spec build_ws_path(Config.t()) :: charlist()
  defp build_ws_path(config) do
    params = [
      {"model", config.model},
      {"language", config.language},
      {"smart_format", to_string(config.smart_format)},
      {"punctuate", to_string(config.punctuate)},
      {"diarize", to_string(config.diarize)},
      {"interim_results", to_string(config.interim_results)},
      {"endpointing", to_string(config.endpointing)},
      {"vad_events", to_string(config.vad_events)},
      {"encoding", config.encoding},
      {"sample_rate", to_string(config.sample_rate)}
    ]

    query = Enum.map_join(params, "&", fn {k, v} -> "#{k}=#{v}" end)
    ~c"/v1/listen?" ++ String.to_charlist(query)
  end

  @spec build_ws_headers(Config.t()) :: [{charlist(), charlist()}]
  defp build_ws_headers(config) do
    [{~c"Authorization", ~c"Token #{config.api_key}"}]
  end

  @spec handle_deepgram_frame(State.t(), binary()) :: State.t()
  defp handle_deepgram_frame(state, frame) do
    case Jason.decode(frame) do
      {:ok, %{"type" => "Results"} = data} ->
        emit_results(state, data)

      {:ok, %{"type" => "UtteranceEnd"}} ->
        # Deepgram signals end of an utterance — emit :end and let stream continue
        send(state.subscriber, {:speech_event, %SpeechEvent{type: :end}})
        state

      {:ok, %{"type" => "SpeechStarted"}} ->
        send(state.subscriber, {:speech_event, %SpeechEvent{type: :start}})
        state

      {:ok, _other} ->
        state

      {:error, reason} ->
        Logger.warning("Failed to decode Deepgram frame: #{inspect(reason)}")
        state
    end
  end

  @spec emit_results(State.t(), map()) :: State.t()
  defp emit_results(state, data) do
    is_final = Map.get(data, "is_final", false)
    transcript = get_in(data, ["channel", "alternatives", Access.at(0), "transcript"]) || ""
    confidence = get_in(data, ["channel", "alternatives", Access.at(0), "confidence"]) || 0.0

    type = if is_final, do: :final, else: :interim

    event = %SpeechEvent{
      type: type,
      text: transcript,
      confidence: confidence,
      language: state.config.language
    }

    send(state.subscriber, {:speech_event, event})
    state
  end

  @spec spawn_mock_stream(pid(), Config.t()) :: pid()
  defp spawn_mock_stream(subscriber, config) do
    server = self()

    spawn(fn ->
      send(subscriber, {:speech_event, %SpeechEvent{type: :start}})
      Process.sleep(50)

      send(
        subscriber,
        {:speech_event,
         %SpeechEvent{type: :interim, text: "Hello", confidence: 0.8, language: config.language}}
      )

      Process.sleep(50)

      send(
        subscriber,
        {:speech_event,
         %SpeechEvent{
           type: :final,
           text: "Hello, how are you?",
           confidence: 0.95,
           language: config.language
         }}
      )

      Process.sleep(10)
      send(subscriber, {:speech_event, %SpeechEvent{type: :end}})
      GenServer.cast(server, :mock_done)
    end)
  end
end

defmodule Livekit.Agents.LLM.OpenAIRealtime do
  @moduledoc """
  OpenAI Realtime API client for direct audio-to-audio conversations.

  Manages a WebSocket connection to `wss://api.openai.com/v1/realtime` using
  Gun, enabling real-time bidirectional audio streaming without a separate
  STT or TTS pipeline. The Realtime API handles speech detection, transcription,
  LLM inference, and speech synthesis in a single round-trip.

  ## Event protocol (sent to subscriber)

    - `{:realtime_audio, binary}` — raw PCM audio chunk from the assistant
    - `{:realtime_text, text}` — text delta from the assistant response
    - `{:realtime_transcript, text}` — input audio transcript from the server
    - `{:realtime_speech_started}` — server detected the start of user speech
    - `{:realtime_speech_stopped}` — server detected the end of user speech
    - `{:realtime_done}` — response generation complete
    - `{:error, reason}` — unrecoverable error

  ## Usage

      alias Livekit.Agents.LLM.OpenAIRealtime
      alias Livekit.Agents.LLM.OpenAIRealtime.Config

      config = %Config{api_key: System.get_env("OPENAI_API_KEY")}
      {:ok, pid} = OpenAIRealtime.start_link({config, self()})
      :ok = OpenAIRealtime.connect(pid)
      :ok = OpenAIRealtime.push_audio(pid, audio_binary)
      :ok = OpenAIRealtime.generate_reply(pid)
  """

  use GenServer
  require Logger

  @openai_host ~c"api.openai.com"
  @openai_port 443

  defmodule Config do
    @moduledoc """
    Configuration for the OpenAI Realtime session.

    ## Fields

    - `:api_key` — OpenAI API key. Required.
    - `:model` — Realtime model name (default: `"gpt-4o-realtime-preview"`).
    - `:instructions` — System prompt / persona instructions for the session.
    - `:voice` — TTS voice: `"alloy"`, `"echo"`, `"fable"`, `"onyx"`, `"nova"`, or `"shimmer"`
      (default: `"alloy"`).
    """

    @type t :: %__MODULE__{
            api_key: String.t() | nil,
            model: String.t(),
            instructions: String.t(),
            voice: String.t()
          }

    defstruct api_key: nil,
              model: "gpt-4o-realtime-preview",
              instructions: "You are a helpful AI assistant.",
              voice: "alloy"
  end

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            config: Config.t(),
            subscriber: pid(),
            conn: pid() | nil,
            stream_ref: reference() | nil,
            connected: boolean(),
            session_id: String.t() | nil,
            metrics: map()
          }

    defstruct [
      :config,
      :subscriber,
      conn: nil,
      stream_ref: nil,
      connected: false,
      session_id: nil,
      metrics: %{
        audio_chunks_sent: 0,
        audio_chunks_received: 0,
        replies_generated: 0,
        errors: 0,
        last_activity: nil
      }
    ]
  end

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @doc """
  Starts a `RealtimeSession` GenServer.

  `config` is a `Config` struct. The `subscriber` process (typically `self()`) receives
  all realtime event messages.
  """
  @spec start_link({Config.t(), pid()}) :: GenServer.on_start()
  def start_link({config, subscriber}) do
    GenServer.start_link(__MODULE__, {config, subscriber})
  end

  @doc """
  Establishes the WebSocket connection to the OpenAI Realtime API.

  Returns `:ok` once the connection handshake starts.
  """
  @spec connect(pid()) :: :ok
  def connect(pid) do
    GenServer.cast(pid, :connect)
  end

  @doc """
  Sends raw audio bytes to the server via the `input_audio_buffer.append` event.

  `audio` must be PCM16 mono at 24 kHz (OpenAI Realtime requirement). Audio is
  Base64-encoded before being sent over the WebSocket JSON channel.
  """
  @spec push_audio(pid(), binary()) :: :ok
  def push_audio(pid, audio) when is_binary(audio) do
    GenServer.cast(pid, {:push_audio, audio})
  end

  @doc """
  Sends a `response.create` event to request a model reply.

  The server will generate a response based on the accumulated
  `input_audio_buffer` and conversation history.
  """
  @spec generate_reply(pid()) :: :ok
  def generate_reply(pid) do
    GenServer.cast(pid, :generate_reply)
  end

  @doc """
  Gracefully closes the WebSocket connection and stops the GenServer.
  """
  @spec disconnect(pid()) :: :ok
  def disconnect(pid) do
    GenServer.cast(pid, :disconnect)
  end

  @doc """
  Returns current session metrics.
  """
  @spec get_metrics(pid()) :: map()
  def get_metrics(pid) do
    GenServer.call(pid, :get_metrics, 5_000)
  end

  @doc """
  Validates a `Config` struct.

  Returns `{:error, :missing_api_key}` when the API key is nil or empty.
  Returns `:ok` when the API key is present.
  """
  @spec validate_config(Config.t()) :: :ok | {:error, :missing_api_key}
  def validate_config(%Config{api_key: key}) when key in [nil, ""],
    do: {:error, :missing_api_key}

  def validate_config(%Config{}), do: :ok

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init({config, subscriber}) do
    state = %State{config: config, subscriber: subscriber}
    {:ok, state}
  end

  @impl true
  def handle_cast(:connect, state) do
    path = build_ws_path(state.config)
    headers = build_ws_headers(state.config)

    case :gun.open(@openai_host, @openai_port, %{transport: :tls}) do
      {:ok, conn} ->
        case :gun.await_up(conn, 10_000) do
          {:ok, _protocol} ->
            stream_ref = :gun.ws_upgrade(conn, path, headers)
            {:noreply, %{state | conn: conn, stream_ref: stream_ref}}

          {:error, reason} ->
            Logger.error("OpenAI Realtime Gun connection failed: #{inspect(reason)}")
            send(state.subscriber, {:error, {:connection_failed, reason}})
            {:noreply, bump_error(state)}
        end

      {:error, reason} ->
        Logger.error("OpenAI Realtime Gun open failed: #{inspect(reason)}")
        send(state.subscriber, {:error, {:connection_failed, reason}})
        {:noreply, bump_error(state)}
    end
  end

  def handle_cast({:push_audio, _audio}, %State{connected: false} = state) do
    Logger.warning("OpenAI Realtime: push_audio called before connection established; discarding")
    {:noreply, state}
  end

  def handle_cast({:push_audio, audio}, state) do
    encoded = Base.encode64(audio)

    event =
      Jason.encode!(%{
        "type" => "input_audio_buffer.append",
        "audio" => encoded
      })

    :gun.ws_send(state.conn, state.stream_ref, {:text, event})
    new_metrics = Map.update!(state.metrics, :audio_chunks_sent, &(&1 + 1))
    {:noreply, %{state | metrics: new_metrics}}
  end

  def handle_cast(:generate_reply, %State{connected: false} = state) do
    Logger.warning("OpenAI Realtime: generate_reply called before connection; ignoring")
    {:noreply, state}
  end

  def handle_cast(:generate_reply, state) do
    event = Jason.encode!(%{"type" => "response.create"})
    :gun.ws_send(state.conn, state.stream_ref, {:text, event})
    new_metrics = Map.update!(state.metrics, :replies_generated, &(&1 + 1))
    {:noreply, %{state | metrics: new_metrics}}
  end

  def handle_cast(:disconnect, %State{conn: nil} = state) do
    {:stop, :normal, state}
  end

  def handle_cast(:disconnect, state) do
    :gun.close(state.conn)
    {:stop, :normal, %{state | conn: nil, connected: false}}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  @impl true
  def handle_info(
        {:gun_upgrade, conn, _stream_ref, ["websocket"], _headers},
        %State{conn: conn} = state
      ) do
    Logger.debug("OpenAI Realtime WebSocket connected")

    # Send session.update to configure voice and instructions
    update_event =
      Jason.encode!(%{
        "type" => "session.update",
        "session" => %{
          "modalities" => ["text", "audio"],
          "instructions" => state.config.instructions,
          "voice" => state.config.voice,
          "input_audio_format" => "pcm16",
          "output_audio_format" => "pcm16",
          "turn_detection" => %{
            "type" => "server_vad"
          }
        }
      })

    :gun.ws_send(conn, state.stream_ref, {:text, update_event})
    {:noreply, %{state | connected: true}}
  end

  def handle_info({:gun_ws, conn, _stream_ref, {:text, frame}}, %State{conn: conn} = state) do
    new_state = handle_server_event(state, frame)
    {:noreply, new_state}
  end

  def handle_info(
        {:gun_ws, conn, _stream_ref, {:close, _code, _reason}},
        %State{conn: conn} = state
      ) do
    send(state.subscriber, {:realtime_done})
    {:stop, :normal, %{state | connected: false}}
  end

  def handle_info(
        {:gun_down, conn, _protocol, reason, _killed_streams},
        %State{conn: conn} = state
      ) do
    Logger.warning("OpenAI Realtime WebSocket lost: #{inspect(reason)}")
    send(state.subscriber, {:error, {:connection_lost, reason}})
    {:stop, :normal, %{state | connected: false}}
  end

  def handle_info({:gun_response, _conn, _stream_ref, _is_fin, status, _headers}, state)
      when status >= 400 do
    Logger.error("OpenAI Realtime WebSocket upgrade rejected with status #{status}")
    send(state.subscriber, {:error, {:upgrade_rejected, status}})
    {:stop, :normal, bump_error(state)}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %State{conn: conn}) when not is_nil(conn) do
    :gun.close(conn)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  @spec build_ws_path(Config.t()) :: charlist()
  defp build_ws_path(config) do
    model = config.model
    path = "/v1/realtime?model=#{model}"
    String.to_charlist(path)
  end

  @spec build_ws_headers(Config.t()) :: [{charlist(), charlist()}]
  defp build_ws_headers(config) do
    [
      {~c"Authorization", String.to_charlist("Bearer #{config.api_key}")},
      {~c"OpenAI-Beta", ~c"realtime=v1"}
    ]
  end

  @spec handle_server_event(State.t(), binary()) :: State.t()
  defp handle_server_event(state, frame) do
    case Jason.decode(frame) do
      {:ok, event} ->
        dispatch_event(state, event)

      {:error, reason} ->
        Logger.warning("OpenAI Realtime: failed to decode frame: #{inspect(reason)}")
        state
    end
  end

  @spec dispatch_event(State.t(), map()) :: State.t()
  defp dispatch_event(state, %{"type" => "session.created", "session" => session}) do
    session_id = Map.get(session, "id", "unknown")
    Logger.debug("OpenAI Realtime session created: #{session_id}")
    %{state | session_id: session_id}
  end

  defp dispatch_event(state, %{"type" => "response.audio.delta", "delta" => delta}) do
    case Base.decode64(delta) do
      {:ok, audio_bytes} ->
        send(state.subscriber, {:realtime_audio, audio_bytes})
        new_metrics = Map.update!(state.metrics, :audio_chunks_received, &(&1 + 1))
        %{state | metrics: new_metrics}

      :error ->
        Logger.warning("OpenAI Realtime: failed to decode audio delta")
        state
    end
  end

  defp dispatch_event(state, %{"type" => "response.text.delta", "delta" => delta}) do
    send(state.subscriber, {:realtime_text, delta})
    state
  end

  defp dispatch_event(state, %{
         "type" => "conversation.item.input_audio_transcription.completed",
         "transcript" => transcript
       }) do
    send(state.subscriber, {:realtime_transcript, transcript})
    state
  end

  defp dispatch_event(state, %{"type" => "input_audio_buffer.speech_started"}) do
    send(state.subscriber, {:realtime_speech_started})
    state
  end

  defp dispatch_event(state, %{"type" => "input_audio_buffer.speech_stopped"}) do
    send(state.subscriber, {:realtime_speech_stopped})
    state
  end

  defp dispatch_event(state, %{"type" => "response.done"}) do
    send(state.subscriber, {:realtime_done})
    state
  end

  defp dispatch_event(state, %{"type" => "error", "error" => error}) do
    Logger.error("OpenAI Realtime server error: #{inspect(error)}")
    send(state.subscriber, {:error, {:server_error, error}})
    bump_error(state)
  end

  defp dispatch_event(state, _event) do
    # Ignore unknown/unhandled events
    state
  end

  @spec bump_error(State.t()) :: State.t()
  defp bump_error(state) do
    new_metrics =
      state.metrics
      |> Map.update!(:errors, &(&1 + 1))
      |> Map.put(:last_activity, DateTime.utc_now())

    %{state | metrics: new_metrics}
  end
end

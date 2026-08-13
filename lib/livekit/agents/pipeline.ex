defmodule Livekit.Agents.Pipeline do
  @moduledoc """
  GenServer that orchestrates the full STT -> LLM -> TTS voice pipeline.

  `Pipeline` accepts raw audio frames via `push_frame/2` (non-blocking cast),
  classifies each frame with `EnergyVAD`, forwards it to `TurnDetector`, and
  reacts to `{:turn_end, frames}` events by running the full processing chain
  asynchronously via `Task.async/1` so the GenServer loop is never blocked.

  ## Processing Chain

      push_frame/2  ->  EnergyVAD.classify/2  ->  TurnDetector.push_frame/2
                                                           |
                                         {:turn_end, frames} (from TurnDetector)
                                                           |
                                            Task.async: STT -> LLM -> TTS
                                                           |
                                         {:pipeline_audio, AudioFrame.t()} sent to subscriber

  ## Interruption

  If a new speech frame arrives while a `Task` is running (status `:processing`
  or `:speaking`), the active task is shut down immediately and the
  `TurnDetector` is reset, preventing stale `{:turn_end, _}` messages.

  ## Provider Injection

  Providers are configured as `{module, config_map}` tuples. Any module that
  implements the `Livekit.Agents.STT`, `Livekit.Agents.LLM`, or
  `Livekit.Agents.TTS` behaviour can be swapped in without changes to this
  module.

  ## Telemetry

  Three `:telemetry` events are emitted during each successful turn:

  - `[:livekit, :agents, :pipeline, :stt_complete]`
  - `[:livekit, :agents, :pipeline, :llm_first_token]`
  - `[:livekit, :agents, :pipeline, :tts_start]`

  ## Usage

      config = %Livekit.Agents.Pipeline.Config{
        stt: {MySTT, %{api_key: "..."}},
        llm: {MyLLM, %{api_key: "..."}},
        tts: {MyTTS, %{api_key: "..."}}
      }
      {:ok, pid} = Livekit.Agents.Pipeline.start_link(config)
      Livekit.Agents.Pipeline.push_frame(pid, audio_frame)
  """

  use GenServer
  require Logger

  alias Livekit.Agents.{AudioFrame, ChatContext}
  alias Livekit.Agents.ChatContext.FunctionCall
  alias Livekit.Agents.Pipeline.{EnergyVAD, TurnDetector}

  # What Whisper-family models emit when handed a few seconds of room tone.
  # They are not transcriptions, they are the model's favourite guesses, and
  # answering them makes the agent talk to traffic.
  @transcription_noise ["you", "thank you.", "thanks for watching!", "bye.", ".", "..."]

  # ---------------------------------------------------------------------------
  # Config struct
  # ---------------------------------------------------------------------------

  defmodule Config do
    @moduledoc """
    Configuration for `Livekit.Agents.Pipeline`.

    ## Fields

    - `:stt` — `{module, config_map}` tuple for the STT provider (required).
    - `:llm` — `{module, config_map}` tuple for the LLM provider (required).
    - `:tts` — `{module, config_map}` tuple for the TTS provider (required).
    - `:subscriber` — PID that receives `{:pipeline_audio, AudioFrame.t()}` output.
      Defaults to `nil` (audio is discarded).
    - `:greeting` — text the agent speaks as soon as the pipeline starts,
      before anybody has said anything. Defaults to `nil` (the agent waits).
    - `:vad_threshold` — RMS amplitude threshold for silence detection. Defaults to `0.01`.
    - `:silence_ms` — Milliseconds of silence after which a turn ends. Defaults to `500`.
    - `:stt_opts` — Extra keyword opts forwarded to the STT provider's `transcribe/2`.
    - `:llm_opts` — Extra keyword opts forwarded to the LLM provider's `chat/2`.
    - `:tts_opts` — Extra keyword opts forwarded to the TTS provider's `synthesize/2`.
    - `:greeting_audio` — Optional PCM 16-bit audio of the greeting, recorded in
      advance. When set the greeting is played rather than synthesised, and
      `:greeting` is used only as the chat-context record of what was said.
    - `:greeting_sample_rate` — Sample rate of `:greeting_audio`. Defaults to
      the TTS provider's.
    - `:on_turn` — Optional `fun(user_text, assistant_text)` called after each
      completed turn. The pipeline holds the transcript only in memory and it
      dies with the room, so anything that needs to keep the conversation —
      persistence, analytics, a CRM — hooks in here.
    """

    @type provider :: {module(), map()}

    @type t :: %__MODULE__{
            stt: provider(),
            llm: provider(),
            tts: provider(),
            subscriber: pid() | nil,
            vad_threshold: float(),
            silence_ms: pos_integer(),
            stt_opts: keyword(),
            llm_opts: keyword(),
            tts_opts: keyword(),
            on_turn: (String.t(), String.t() -> any()) | nil
          }

    defstruct [
      :stt,
      :llm,
      :tts,
      subscriber: nil,
      greeting: nil,
      vad_threshold: 0.01,
      silence_ms: 500,
      stt_opts: [],
      llm_opts: [],
      tts_opts: [],
      on_turn: nil,
      greeting_audio: nil,
      greeting_sample_rate: nil
    ]
  end

  # ---------------------------------------------------------------------------
  # State struct
  # ---------------------------------------------------------------------------

  defmodule State do
    @moduledoc false

    @type pipeline_status :: :idle | :processing | :speaking

    @type t :: %__MODULE__{
            config: Config.t(),
            vad_config: term(),
            turn_detector: pid(),
            chat_context: ChatContext.t(),
            active_task: Task.t() | nil,
            status: pipeline_status(),
            metrics: map()
          }

    defstruct [
      :config,
      :vad_config,
      :turn_detector,
      :chat_context,
      active_task: nil,
      # So a re-subscribe cannot make the agent introduce itself twice.
      greeted?: false,
      status: :idle,
      metrics: %{
        turns_processed: 0,
        audio_frames_processed: 0,
        errors: 0,
        last_activity: nil
      }
    ]
  end

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @doc """
  Starts a `Pipeline` GenServer linked to the calling process.

  `config` must be a `%Pipeline.Config{}` struct with `:stt`, `:llm`, and
  `:tts` populated.

  Returns `{:ok, pid}` on success, or `{:error, :missing_providers}` if any
  provider is absent.
  """
  @spec start_link(Config.t()) :: GenServer.on_start()
  def start_link(%Config{} = config), do: GenServer.start_link(__MODULE__, config)

  @doc """
  Pushes an audio frame into the pipeline (non-blocking cast).

  The frame is classified by `EnergyVAD` and forwarded to `TurnDetector`.
  If the frame is classified as `:speech` and a processing task is active, the
  task is cancelled (interruption) before the new frame is processed.
  """
  @spec push_frame(pid(), AudioFrame.t()) :: :ok
  def push_frame(pid, %AudioFrame{} = frame), do: GenServer.cast(pid, {:push_frame, frame})

  @doc """
  Returns the current pipeline metrics map.
  """
  @spec get_metrics(pid()) :: map()
  def get_metrics(pid), do: GenServer.call(pid, :get_metrics, 5_000)

  @doc """
  Returns the current `ChatContext` held by the pipeline.

  Used by `Livekit.Agents.AgentHandoff` to transfer conversation history to a
  new pipeline.
  """
  @spec get_chat_context(pid()) :: ChatContext.t()
  def get_chat_context(pid), do: GenServer.call(pid, :get_chat_context, 5_000)

  @doc """
  Replaces the pipeline's `ChatContext` with the given one.

  Used by `Livekit.Agents.AgentHandoff` to pre-load conversation history into a
  freshly started pipeline.
  """
  @spec set_chat_context(pid(), ChatContext.t()) :: :ok
  def set_chat_context(pid, %ChatContext{} = ctx),
    do: GenServer.call(pid, {:set_chat_context, ctx}, 5_000)

  @doc """
  Stops the pipeline GenServer.
  """
  @spec stop(pid()) :: :ok
  def stop(pid), do: GenServer.stop(pid, :normal, 5_000)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @doc """
  Speaks the configured greeting, once.

  Separate from `set_subscriber/2` because claiming the output and having
  somebody to hear it are different moments. LiveKit dispatches an agent when
  the room is created, which is before the visitor's browser has finished
  connecting; audio published in that gap is played to an empty room and
  discarded, since WebRTC buffers nothing. Call this when a visitor is
  demonstrably present.

  A no-op when no greeting is configured or the agent has already greeted.
  """
  @spec greet(pid()) :: :ok
  def greet(pipeline_pid), do: GenServer.call(pipeline_pid, :greet)

  @doc """
  Redirects synthesised audio to `subscriber`.

  The subscriber cannot be known when the pipeline starts: `RoomIO` is what
  publishes audio into a room, and it needs the pipeline's pid to be built.
  Rather than contort the startup order, RoomIO claims the subscription once
  it exists.
  """
  @spec set_subscriber(pid(), pid()) :: :ok
  def set_subscriber(pipeline_pid, subscriber) when is_pid(subscriber) do
    GenServer.call(pipeline_pid, {:set_subscriber, subscriber})
  end

  @impl true
  def init(%Config{stt: stt, llm: llm, tts: tts})
      when stt == nil or llm == nil or tts == nil do
    Logger.error("Pipeline init failed: stt, llm, and tts providers are all required")
    {:stop, :missing_providers}
  end

  @impl true
  def init(%Config{} = config) do
    # ISSUE-01: Validate that provider configs are non-nil
    {_stt_mod, stt_config} = config.stt
    if is_nil(stt_config), do: raise("STT provider config cannot be nil")

    {_llm_mod, llm_config} = config.llm
    if is_nil(llm_config), do: raise("LLM provider config cannot be nil")

    {_tts_mod, tts_config} = config.tts
    if is_nil(tts_config), do: raise("TTS provider config cannot be nil")
    vad_config = EnergyVAD.new(%{threshold: config.vad_threshold})

    case TurnDetector.start_link(silence_ms: config.silence_ms, subscriber: self()) do
      {:ok, turn_detector_pid} ->
        state = %State{
          config: config,
          vad_config: vad_config,
          turn_detector: turn_detector_pid,
          chat_context: ChatContext.new()
        }

        # Only greet now if somebody is already listening. When an agent is
        # joining a room the subscriber is RoomIO, which cannot exist yet —
        # it needs this pipeline's pid — so greeting here would synthesise
        # the opening line and hand it to a process that drops it. The
        # greeting is deferred to set_subscriber/2 in that case.
        if greeting?(config) and config.subscriber, do: send(self(), :greet)

        {:ok, state}

      {:error, reason} ->
        Logger.error("Pipeline failed to start TurnDetector: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_cast({:push_frame, %AudioFrame{} = frame}, %State{} = state) do
    classification = EnergyVAD.classify(frame, state.vad_config)
    TurnDetector.push_frame(state.turn_detector, {classification, frame})

    state =
      if classification == :speech and state.active_task != nil do
        Logger.debug("Pipeline: interruption detected — cancelling active task")
        Task.shutdown(state.active_task, :brutal_kill)
        TurnDetector.reset(state.turn_detector)
        %{state | active_task: nil, status: :idle}
      else
        state
      end

    updated_metrics =
      state.metrics
      |> Map.update!(:audio_frames_processed, &(&1 + 1))
      |> Map.put(:last_activity, DateTime.utc_now())

    {:noreply, %{state | metrics: updated_metrics}}
  end

  @impl true
  # The agent speaks first.
  #
  # For an agent someone was sent to — a QR code on a For Sale board, a
  # support widget they clicked — silence on arrival is indistinguishable from
  # a broken page. Whoever arrived does not know whether to start talking, and
  # a microphone permission prompt they have just accepted makes it worse.
  #
  # The greeting is recorded in the chat context as an assistant message, so
  # the model's next turn knows what it has already said and does not
  # introduce itself twice.
  def handle_info(:greet, %State{greeted?: true} = state), do: {:noreply, state}

  # An opening line that was recorded in advance. Nothing to synthesise, so the
  # visitor hears it as soon as anyone is there to hear it, instead of waiting
  # out a round trip to a speech API at the start of every conversation.
  def handle_info(:greet, %State{config: %Config{greeting_audio: audio}} = state)
      when is_binary(audio) and byte_size(audio) > 0 do
    state = %{state | greeted?: true}

    Logger.info("Pipeline: greeting from a recording, #{byte_size(audio)} bytes")

    if state.config.subscriber do
      send(
        state.config.subscriber,
        {:pipeline_audio,
         %AudioFrame{data: audio, sample_rate: greeting_sample_rate(state.config)}}
      )
    end

    # Still into the chat context: the model has to know what has already been
    # said to the visitor, or it opens by saying it again.
    ctx =
      ChatContext.add(
        state.chat_context,
        ChatContext.new_message(:assistant, [state.config.greeting])
      )

    {:noreply, %{state | chat_context: ctx}}
  end

  def handle_info(:greet, %State{} = state) do
    greeting = state.config.greeting
    state = %{state | greeted?: true}

    # The greeting is the whole voice path in miniature — TTS, then the hop to
    # whoever publishes. Both ends are logged: a silent room is otherwise
    # indistinguishable from a slow one.
    Logger.info("Pipeline: synthesising greeting (#{byte_size(greeting)} chars)")

    case do_tts(greeting, state.config, state.config.tts_opts) do
      {:ok, audio} when byte_size(audio) > 0 ->
        Logger.info(
          "Pipeline: greeting synthesised, #{byte_size(audio)} bytes, " <>
            "subscriber=#{inspect(state.config.subscriber)}"
        )

        if state.config.subscriber do
          send(
            state.config.subscriber,
            {:pipeline_audio,
             %AudioFrame{data: audio, sample_rate: tts_sample_rate(state.config)}}
          )
        end

        ctx =
          ChatContext.add(
            state.chat_context,
            ChatContext.new_message(:assistant, [greeting])
          )

        {:noreply, %{state | chat_context: ctx}}

      other ->
        # A greeting that fails to synthesise must not take the session down:
        # the visitor can still speak first, which is strictly better than a
        # dead room.
        Logger.warning("Pipeline greeting failed: #{inspect(other)}")
        {:noreply, state}
    end
  end

  def handle_info({:turn_start, _timestamp_us}, %State{} = state) do
    updated_metrics = Map.put(state.metrics, :last_activity, DateTime.utc_now())
    {:noreply, %{state | metrics: updated_metrics}}
  end

  @impl true
  def handle_info({:turn_end, _frames}, %State{status: :processing} = state) do
    # ISSUE-14: Discard stale turn_end while already processing a turn
    Logger.debug("Pipeline: ignoring stale turn_end — already processing")
    {:noreply, state}
  end

  @impl true
  def handle_info({:turn_end, frames}, %State{} = state) do
    config = state.config
    chat_context = state.chat_context

    # The first observable sign that the agent heard anything at all. Without
    # it, "the visitor spoke and nothing happened" and "the visitor's audio
    # never arrived" look identical from the logs.
    Logger.info("Pipeline: turn ended, #{length(frames)} frames")

    task =
      Task.async(fn ->
        with {:ok, speech_event} <- do_stt(frames, config, config.stt_opts),
             :ok <- emit_telemetry(:stt_complete, %{text: speech_event.text}),
             :speech <- classify_transcript(speech_event.text),
             {:ok, llm_response} <-
               do_llm(
                 ChatContext.add(
                   chat_context,
                   ChatContext.new_message(:user, [speech_event.text])
                 ),
                 config,
                 config.llm_opts
               ) do
          # ISSUE-19: Handle FunctionCall responses from LLM
          case llm_response do
            %FunctionCall{} ->
              Logger.warning(
                "Pipeline received FunctionCall but tool execution not yet supported in pipeline"
              )

              {:ok, speech_event.text, nil, nil}

            _ ->
              # ISSUE-02: Convert content list to string before passing to TTS
              text = content_to_string(llm_response.content)

              with :ok <- emit_telemetry(:llm_first_token, %{role: llm_response.role}),
                   {:ok, audio_binary} <- do_tts(text, config, config.tts_opts),
                   :ok <- emit_telemetry(:tts_start, %{bytes: byte_size(audio_binary)}) do
                {:ok, speech_event.text, llm_response, audio_binary}
              end
          end
        end
      end)

    {:noreply, %{state | active_task: task, status: :processing}}
  end

  @impl true
  def handle_info({ref, result}, %State{active_task: %Task{ref: task_ref}} = state)
      when ref == task_ref do
    Process.demonitor(ref, [:flush])

    state =
      case result do
        :no_speech ->
          # A door, a car, a cough. The turn detector hears energy; only the
          # transcriber knows whether it was language. Answering anyway makes
          # the agent interrupt a silent street with "your message didn't come
          # through", which is worse than saying nothing.
          Logger.info("Pipeline: turn carried no speech, staying quiet")
          %{state | active_task: nil, status: :idle}

        {:ok, user_text, nil, nil} ->
          # FunctionCall response — no audio to send, context unchanged for now
          Logger.debug("Pipeline turn complete (FunctionCall) — user: #{inspect(user_text)}")
          updated_metrics = Map.update!(state.metrics, :turns_processed, &(&1 + 1))
          %{state | metrics: updated_metrics, active_task: nil, status: :idle}

        {:ok, user_text, llm_response, audio_binary} ->
          Logger.info(
            "Pipeline turn complete — user: #{inspect(user_text)}, assistant: #{inspect(llm_response.content)}"
          )

          # BOTH sides of the turn. The user message was previously added only
          # to the local context handed to the LLM inside the task, and never
          # made it back into state — so a conversation accumulated the
          # assistant's replies and forgot every question that produced them.
          # Nothing failed; the model just lost the thread a few turns in,
          # which is the hardest kind of bug to notice from the outside.
          updated_ctx =
            state.chat_context
            |> ChatContext.add(ChatContext.new_message(:user, [user_text]))
            |> ChatContext.add(
              ChatContext.new_message(:assistant, [content_to_string(llm_response.content)])
            )

          if state.config.subscriber do
            audio_frame = %AudioFrame{
              data: audio_binary,
              sample_rate: tts_sample_rate(state.config)
            }

            send(state.config.subscriber, {:pipeline_audio, audio_frame})
          end

          # Outside the pipeline the transcript exists nowhere else: this process
          # holds it in memory and it dies with the room. Failures here are the
          # caller's problem to log, never the agent's to crash on — a lost
          # transcript must not end a conversation mid-sentence.
          if is_function(state.config.on_turn, 2) do
            try do
              state.config.on_turn.(user_text, content_to_string(llm_response.content))
            rescue
              e -> Logger.error("Pipeline on_turn raised: #{inspect(e)}")
            end
          end

          updated_metrics = Map.update!(state.metrics, :turns_processed, &(&1 + 1))

          %{
            state
            | chat_context: updated_ctx,
              metrics: updated_metrics,
              active_task: nil,
              status: :idle
          }

        {:error, reason} ->
          Logger.error("Pipeline processing error: #{inspect(reason)}")
          # ISSUE-18: Surface errors to subscriber
          if state.config.subscriber do
            send(state.config.subscriber, {:pipeline_error, reason})
          end

          updated_metrics = Map.update!(state.metrics, :errors, &(&1 + 1))
          %{state | metrics: updated_metrics, active_task: nil, status: :idle}
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({ref, _result}, %State{} = state) when is_reference(ref) do
    # Stale task result — task was already cancelled (interruption). Flush monitor.
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, :normal}, %State{} = state) do
    # Normal task exit (already handled via the ref message above).
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, %State{} = state) do
    Logger.warning("Pipeline: active task exited abnormally — #{inspect(reason)}")
    updated_metrics = Map.update!(state.metrics, :errors, &(&1 + 1))
    {:noreply, %{state | metrics: updated_metrics, active_task: nil, status: :idle}}
  end

  @impl true
  def handle_call({:set_subscriber, subscriber}, _from, %State{} = state) do
    state = %{state | config: %{state.config | subscriber: subscriber}}

    # Deliberately no greeting here. Claiming the output only proves the audio
    # has somewhere to go, not that anybody is in the room — see greet/1.
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:greet, _from, %State{} = state) do
    if greeting?(state.config) and not state.greeted? and state.config.subscriber do
      send(self(), :greet)
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, %State{} = state) do
    {:reply, state.metrics, state}
  end

  @impl true
  def handle_call(:get_chat_context, _from, %State{} = state) do
    {:reply, state.chat_context, state}
  end

  @impl true
  def handle_call({:set_chat_context, %ChatContext{} = ctx}, _from, %State{} = state) do
    {:reply, :ok, %{state | chat_context: ctx}}
  end

  # ISSUE-04/16: Shut down active task and turn detector on termination
  @impl true
  def terminate(_reason, state) do
    if state.active_task, do: Task.shutdown(state.active_task, :brutal_kill)

    if state.turn_detector && Process.alive?(state.turn_detector) do
      GenServer.stop(state.turn_detector, :normal, 1_000)
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  # ISSUE-02: Normalize LLM content (list or binary) to a plain string for TTS
  @spec content_to_string(term()) :: String.t()
  defp content_to_string([single]) when is_binary(single), do: single
  defp content_to_string(parts) when is_list(parts), do: Enum.map_join(parts, " ", &to_string/1)
  defp content_to_string(binary) when is_binary(binary), do: binary
  defp content_to_string(_), do: ""

  @spec do_stt([AudioFrame.t()], Config.t(), keyword()) ::
          {:ok, Livekit.Agents.STT.SpeechEvent.t()} | {:error, term()}
  defp do_stt(frames, config, opts) do
    {stt_module, stt_config} = config.stt
    audio_binary = frames |> Enum.map(& &1.data) |> IO.iodata_to_binary()
    stt_module.transcribe(audio_binary, Keyword.merge(opts, config: stt_config))
  end

  @spec do_llm(ChatContext.t(), Config.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  defp do_llm(chat_context, config, opts) do
    {llm_module, llm_config} = config.llm
    llm_module.chat(chat_context, Keyword.merge(opts, config: llm_config))
  end

  @spec do_tts(String.t(), Config.t(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  # Transcribers are obliging: handed noise, they return an empty string, and
  # handed near-silence they hallucinate a stock phrase. Neither is a turn.
  defp classify_transcript(text) do
    trimmed = String.trim(text || "")

    cond do
      trimmed == "" -> :no_speech
      String.downcase(trimmed) in @transcription_noise -> :no_speech
      true -> :speech
    end
  end

  defp do_tts(text, config, opts) do
    {tts_module, tts_config} = config.tts
    tts_module.synthesize(text, Keyword.merge(opts, config: tts_config))
  end

  # A recording carries its own rate, which need not be the TTS provider's.
  defp greeting_sample_rate(%Config{greeting_sample_rate: rate}) when is_integer(rate), do: rate
  defp greeting_sample_rate(%Config{} = config), do: tts_sample_rate(config)

  # The rate the TTS provider actually returns, not the AudioFrame default.
  # Publishing 24kHz speech labelled 48kHz creates the track at the wrong rate
  # and the agent plays back at double speed.
  defp tts_sample_rate(%Config{tts: {_module, %{sample_rate: rate}}}) when is_integer(rate),
    do: rate

  defp tts_sample_rate(%Config{}), do: 48_000

  defp greeting?(%Config{greeting: g}), do: is_binary(g) and String.trim(g) != ""

  @spec emit_telemetry(atom(), map()) :: :ok
  defp emit_telemetry(event, measurements) do
    event_name = [:livekit, :agents, :pipeline, event]
    metadata = %{monotonic_time: System.monotonic_time()}
    :telemetry.execute(event_name, measurements, metadata)
    :ok
  end
end

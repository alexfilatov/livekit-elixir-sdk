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
            tts_opts: keyword()
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
      tts_opts: []
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

        # Greet after init returns, not during it: synthesis is a network call,
        # and a GenServer that blocks in init/1 blocks whoever started it —
        # here, the agent session joining the room.
        if greeting?(config), do: send(self(), :greet)

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
  def handle_info(:greet, %State{} = state) do
    greeting = state.config.greeting

    case do_tts(greeting, state.config, state.config.tts_opts) do
      {:ok, audio} when byte_size(audio) > 0 ->
        if state.config.subscriber do
          send(state.config.subscriber, {:pipeline_audio, %AudioFrame{data: audio}})
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

    task =
      Task.async(fn ->
        with {:ok, speech_event} <- do_stt(frames, config, config.stt_opts),
             :ok <- emit_telemetry(:stt_complete, %{text: speech_event.text}),
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
        {:ok, user_text, nil, nil} ->
          # FunctionCall response — no audio to send, context unchanged for now
          Logger.debug("Pipeline turn complete (FunctionCall) — user: #{inspect(user_text)}")
          updated_metrics = Map.update!(state.metrics, :turns_processed, &(&1 + 1))
          %{state | metrics: updated_metrics, active_task: nil, status: :idle}

        {:ok, user_text, llm_response, audio_binary} ->
          Logger.debug(
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
            audio_frame = %AudioFrame{data: audio_binary}
            send(state.config.subscriber, {:pipeline_audio, audio_frame})
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
    {:reply, :ok, %{state | config: %{state.config | subscriber: subscriber}}}
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
  defp do_tts(text, config, opts) do
    {tts_module, tts_config} = config.tts
    tts_module.synthesize(text, Keyword.merge(opts, config: tts_config))
  end

  defp greeting?(%Config{greeting: g}), do: is_binary(g) and String.trim(g) != ""

  @spec emit_telemetry(atom(), map()) :: :ok
  defp emit_telemetry(event, measurements) do
    event_name = [:livekit, :agents, :pipeline, event]
    metadata = %{monotonic_time: System.monotonic_time()}
    :telemetry.execute(event_name, measurements, metadata)
    :ok
  end
end

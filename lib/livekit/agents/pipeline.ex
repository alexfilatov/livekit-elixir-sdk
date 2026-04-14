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
  Stops the pipeline GenServer.
  """
  @spec stop(pid()) :: :ok
  def stop(pid), do: GenServer.stop(pid, :normal, 5_000)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%Config{stt: stt, llm: llm, tts: tts})
      when stt == nil or llm == nil or tts == nil do
    Logger.error("Pipeline init failed: stt, llm, and tts providers are all required")
    {:stop, :missing_providers}
  end

  @impl true
  def init(%Config{} = config) do
    vad_config = EnergyVAD.new(%{threshold: config.vad_threshold})

    case TurnDetector.start_link(silence_ms: config.silence_ms, subscriber: self()) do
      {:ok, turn_detector_pid} ->
        state = %State{
          config: config,
          vad_config: vad_config,
          turn_detector: turn_detector_pid,
          chat_context: ChatContext.new()
        }

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
  def handle_info({:turn_start, _timestamp_us}, %State{} = state) do
    updated_metrics = Map.put(state.metrics, :last_activity, DateTime.utc_now())
    {:noreply, %{state | metrics: updated_metrics}}
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
               ),
             :ok <- emit_telemetry(:llm_first_token, %{role: llm_response.role}),
             {:ok, audio_binary} <- do_tts(llm_response.content, config, config.tts_opts),
             :ok <- emit_telemetry(:tts_start, %{bytes: byte_size(audio_binary)}) do
          {:ok, speech_event.text, llm_response, audio_binary}
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
        {:ok, user_text, llm_response, audio_binary} ->
          Logger.debug(
            "Pipeline turn complete — user: #{inspect(user_text)}, assistant: #{inspect(llm_response.content)}"
          )

          updated_ctx =
            ChatContext.add(
              state.chat_context,
              ChatContext.new_message(:assistant, [llm_response.content])
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
  def handle_call(:get_metrics, _from, %State{} = state) do
    {:reply, state.metrics, state}
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  @spec do_stt([AudioFrame.t()], Config.t(), keyword()) ::
          {:ok, Livekit.Agents.STT.SpeechEvent.t()} | {:error, term()}
  defp do_stt(frames, config, opts) do
    {stt_module, _stt_config} = config.stt
    audio_binary = frames |> Enum.map(& &1.data) |> IO.iodata_to_binary()
    stt_module.transcribe(audio_binary, opts)
  end

  @spec do_llm(ChatContext.t(), Config.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  defp do_llm(chat_context, config, opts) do
    {llm_module, _llm_config} = config.llm
    llm_module.chat(chat_context, opts)
  end

  @spec do_tts(String.t(), Config.t(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  defp do_tts(text, config, opts) do
    {tts_module, _tts_config} = config.tts
    tts_module.synthesize(text, opts)
  end

  @spec emit_telemetry(atom(), map()) :: :ok
  defp emit_telemetry(event, measurements) do
    event_name = [:livekit, :agents, :pipeline, event]
    metadata = %{monotonic_time: System.monotonic_time()}
    :telemetry.execute(event_name, measurements, metadata)
    :ok
  end
end

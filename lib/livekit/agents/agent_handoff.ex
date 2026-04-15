defmodule Livekit.Agents.AgentHandoff do
  @moduledoc """
  Manages the lifecycle of handing off a conversation from one agent to another.

  Agent handoff transfers the `ChatContext` (conversation history) and audio routing
  from a running `Pipeline` to a new pipeline configured with different providers.
  This enables multi-agent conversations where a specialist agent can take over
  from a generalist, or where language/capability transitions are needed.

  ## Handoff Modes

  - **Warm handoff** (`:warm`) — the new pipeline is started before the old one is
    stopped, minimising silence. The new agent begins as soon as context is transferred.
  - **Cold handoff** (`:cold`) — the current pipeline is stopped cleanly first, then
    the new pipeline is started. A brief silence gap is expected.

  ## Usage

      new_pipeline_config = %Pipeline.Config{
        stt: {MySTT, %{api_key: "..."}},
        llm: {MySpecialistLLM, %{api_key: "..."}},
        tts: {MyTTS, %{api_key: "..."}}
      }

      {:ok, new_pipeline_pid} = AgentHandoff.handoff(
        current_pipeline_pid,
        new_pipeline_config,
        mode: :warm,
        subscriber: self()
      )

  ## Events

  A `Livekit.Agents.Events.AgentHandoff` event is published via
  `Livekit.Agents.EventBus` on every successful handoff, when `:session_id` is
  provided in opts.

  ## Error Handling

  If the new pipeline fails to start the old pipeline is left running unchanged
  and `{:error, reason}` is returned.
  """

  require Logger

  alias Livekit.Agents.{ChatContext, EventBus, Pipeline}
  alias Livekit.Agents.Events.AgentHandoff, as: AgentHandoffEvent

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Transfers conversation context and audio routing from `current_pipeline` to a
  new pipeline built from `new_config`.

  ## Parameters

  - `current_pipeline` — PID of the active `Pipeline` GenServer.
  - `new_config` — `%Pipeline.Config{}` for the incoming agent.
  - `opts` — keyword options:
    - `:mode` — `:warm` (default) or `:cold`.
    - `:subscriber` — PID that receives `{:pipeline_audio, AudioFrame.t()}` from the
      new pipeline. Defaults to `nil` (audio is discarded until the caller wires up
      routing).
    - `:from_agent` — label for the outgoing agent (used in the emitted event). Defaults
      to the PID of `current_pipeline`.
    - `:to_agent` — label for the incoming agent (used in the emitted event). Defaults
      to the atom `:new_agent`.
    - `:session_id` — EventBus session ID for publishing the `AgentHandoff` event.
      If `nil` (default) no event is published.
    - `:timeout` — milliseconds to wait for an active turn to finish before forcing
      the handoff (default `5_000`). In `:cold` mode the pipeline is stopped after
      this deadline.

  ## Returns

  - `{:ok, new_pipeline_pid}` on success.
  - `{:error, reason}` if the new pipeline fails to start.
  """
  @spec handoff(pid(), Pipeline.Config.t(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def handoff(current_pipeline, %Pipeline.Config{} = new_config, opts \\ [])
      when is_pid(current_pipeline) do
    mode = Keyword.get(opts, :mode, :warm)
    subscriber = Keyword.get(opts, :subscriber, nil)
    from_agent = Keyword.get(opts, :from_agent, current_pipeline)
    to_agent = Keyword.get(opts, :to_agent, :new_agent)
    session_id = Keyword.get(opts, :session_id, nil)
    timeout = Keyword.get(opts, :timeout, 5_000)

    Logger.info(
      "[AgentHandoff] Starting #{mode} handoff from #{inspect(from_agent)} to #{inspect(to_agent)}"
    )

    with {:ok, chat_context} <- extract_context(current_pipeline, timeout),
         {:ok, new_pipeline_pid} <- start_new_pipeline(new_config, chat_context, subscriber),
         :ok <- stop_old_pipeline(current_pipeline, mode) do
      emit_handoff_event(from_agent, to_agent, mode, chat_context, session_id)

      Logger.info("[AgentHandoff] Handoff complete — new pipeline: #{inspect(new_pipeline_pid)}")

      {:ok, new_pipeline_pid}
    else
      {:error, reason} ->
        Logger.error("[AgentHandoff] Handoff failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  # Wait for the current pipeline to become idle, then extract its ChatContext.
  # If the pipeline does not settle within `timeout` ms we proceed anyway —
  # the context we read may be missing the in-flight turn's assistant reply.
  @spec extract_context(pid(), pos_integer()) :: {:ok, ChatContext.t()} | {:error, term()}
  defp extract_context(pipeline_pid, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_for_idle(pipeline_pid, deadline)
    get_chat_context(pipeline_pid)
  end

  defp wait_for_idle(pipeline_pid, deadline) do
    if Process.alive?(pipeline_pid) do
      check_deadline_and_continue(pipeline_pid, deadline)
    end
  end

  defp check_deadline_and_continue(pipeline_pid, deadline) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      Logger.warning("[AgentHandoff] Timeout waiting for pipeline idle — proceeding anyway")
    else
      poll_if_active(pipeline_pid, deadline)
    end
  end

  defp poll_if_active(pipeline_pid, deadline) do
    metrics = Pipeline.get_metrics(pipeline_pid)

    if Map.get(metrics, :active_task_running, false) do
      Process.sleep(50)
      wait_for_idle(pipeline_pid, deadline)
    end
  end

  @spec get_chat_context(pid()) :: {:ok, ChatContext.t()} | {:error, term()}
  defp get_chat_context(pipeline_pid) do
    if Process.alive?(pipeline_pid) do
      context = Pipeline.get_chat_context(pipeline_pid)
      {:ok, context}
    else
      {:error, :pipeline_not_alive}
    end
  rescue
    e -> {:error, {:context_extraction_failed, e}}
  end

  # Start a new Pipeline pre-loaded with the transferred ChatContext.
  # Uses Process.flag(:trap_exit, true) temporarily so that a failed
  # Pipeline.start_link (which sends an EXIT to the caller) is caught as
  # {:error, reason} rather than crashing the calling process.
  @spec start_new_pipeline(Pipeline.Config.t(), ChatContext.t(), pid() | nil) ::
          {:ok, pid()} | {:error, term()}
  defp start_new_pipeline(%Pipeline.Config{} = config, %ChatContext{} = chat_context, subscriber) do
    config_with_subscriber = %{config | subscriber: subscriber}
    prev_trap = Process.flag(:trap_exit, true)

    result =
      case Pipeline.start_link(config_with_subscriber) do
        {:ok, pid} ->
          :ok = Pipeline.set_chat_context(pid, chat_context)
          {:ok, pid}

        {:error, reason} ->
          {:error, {:new_pipeline_start_failed, reason}}
      end

    # Drain any EXIT messages that arrived while trap_exit was true
    receive do
      {:EXIT, _pid, _reason} -> :ok
    after
      0 -> :ok
    end

    Process.flag(:trap_exit, prev_trap)
    result
  end

  # Stop the old pipeline after the new one is already running (warm) or
  # before (cold). In both cases we stop it if still alive.
  @spec stop_old_pipeline(pid(), :warm | :cold) :: :ok
  defp stop_old_pipeline(pipeline_pid, _mode) do
    if Process.alive?(pipeline_pid) do
      Pipeline.stop(pipeline_pid)
    end

    :ok
  end

  @spec emit_handoff_event(term(), term(), :warm | :cold, ChatContext.t(), String.t() | nil) ::
          :ok
  defp emit_handoff_event(_from_agent, _to_agent, _mode, _chat_context, nil), do: :ok

  defp emit_handoff_event(from_agent, to_agent, mode, chat_context, session_id) do
    event = %AgentHandoffEvent{
      from_agent: from_agent,
      to_agent: to_agent,
      mode: mode,
      context_size: length(chat_context.items),
      timestamp: DateTime.utc_now()
    }

    EventBus.publish(session_id, event)
  end
end

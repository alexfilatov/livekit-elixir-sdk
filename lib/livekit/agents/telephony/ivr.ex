defmodule Livekit.Agents.Telephony.IVR do
  @moduledoc """
  IVR (Interactive Voice Response) workflow engine for telephony agents.

  Provides a `Behaviour` for defining step-based IVR workflows and an `IVRRunner`
  `GenServer` that executes those workflows step by step.

  ## Workflow Behaviour

  Implement the `Livekit.Agents.Telephony.IVR` behaviour to define a workflow:

      defmodule MyIVR do
        @behaviour Livekit.Agents.Telephony.IVR

        @impl true
        def handle_step(:greeting, _ctx) do
          {:speak, "Welcome! Press 1 for sales, 2 for support.", next: :menu}
        end

        @impl true
        def handle_step(:menu, %{last_digits: "1"}) do
          {:transfer, "+15551111111"}
        end

        @impl true
        def handle_step(:menu, %{last_digits: "2"}) do
          {:transfer, "+15552222222"}
        end

        @impl true
        def on_complete(:transferred, _ctx), do: :ok

        @impl true
        def on_timeout(step, _ctx) do
          {:speak, "Sorry, I didn't catch that.", next: step}
        end
      end

  ## Built-in Step Types

  Workflows return one of:

  - `{:speak, text}` — Speak text and wait (no next step, workflow ends).
  - `{:speak, text, next: step}` — Speak text then advance to `step`.
  - `{:collect_digits, opts}` — Collect DTMF digits (`:prompt`, `:next`, `:terminator`).
  - `{:collect_speech, opts}` — Collect speech input (`:prompt`, `:next`).
  - `{:transfer, phone_number}` — Transfer call to another number.
  - `{:hangup, reason}` — End the call.
  - `:done` — Workflow complete.

  ## IVRRunner

  Use `IVRRunner` to execute a workflow module as a supervised `GenServer`.

      {:ok, runner} = IVRRunner.start_link(
        module: MyIVR,
        initial_step: :greeting,
        context: %{caller: "+15550001111"},
        subscriber: self()
      )

  The runner sends `{:ivr_action, action}` messages to the subscriber for each
  step action, and `{:ivr_complete, reason}` when the workflow finishes.
  """

  @doc """
  Process the current IVR step and return the next action.

  Called by `IVRRunner` each time a step is executed.

  ## Parameters

  - `step` — The current step atom (e.g. `:greeting`, `:collect_name`).
  - `context` — Map of workflow context (accumulated data, last digits, etc.).

  ## Returns

  One of:
  - `{:speak, text}` — Speak text and finish.
  - `{:speak, text, next: step}` — Speak text and advance to `step`.
  - `{:collect_digits, opts}` — Collect DTMF digits.
  - `{:collect_speech, opts}` — Collect speech.
  - `{:transfer, phone_number}` — Transfer call.
  - `{:hangup, reason}` — Hang up.
  - `:done` — Workflow complete.
  """
  @callback handle_step(step :: atom(), context :: map()) ::
              {:speak, String.t()}
              | {:speak, String.t(), [{:next, atom()}]}
              | {:collect_digits, keyword()}
              | {:collect_speech, keyword()}
              | {:transfer, String.t()}
              | {:hangup, term()}
              | :done

  @doc """
  Called when the workflow finishes (all steps complete or `:done` returned).

  ## Parameters

  - `reason` — Completion reason atom (e.g. `:completed`, `:transferred`, `:hung_up`).
  - `context` — Final workflow context map.
  """
  @callback on_complete(reason :: atom(), context :: map()) :: :ok

  @doc """
  Called when a step times out waiting for input.

  Should return a new action (typically a retry prompt or `:hangup`).

  ## Parameters

  - `step` — The step that timed out.
  - `context` — Current workflow context map.
  """
  @callback on_timeout(step :: atom(), context :: map()) ::
              {:speak, String.t()}
              | {:speak, String.t(), [{:next, atom()}]}
              | {:collect_digits, keyword()}
              | {:collect_speech, keyword()}
              | {:hangup, term()}
              | :done

  defmodule IVRRunner do
    @moduledoc """
    GenServer that executes an IVR workflow module step by step.

    Sends `{:ivr_action, action}` messages to the configured subscriber for
    each step action so the host agent can act on them (play TTS, collect input, etc.).

    Sends `{:ivr_complete, reason}` when the workflow finishes.

    ## Usage

        {:ok, runner} = IVRRunner.start_link(
          module: MyIVR,
          initial_step: :greeting,
          context: %{},
          subscriber: self()
        )

        # Advance the workflow with new context (e.g. after collecting digits)
        IVRRunner.advance(runner, %{last_digits: "1"})

        # Signal that the current step timed out
        IVRRunner.timeout(runner)
    """

    use GenServer
    require Logger

    defmodule Config do
      @moduledoc false

      @type t :: %__MODULE__{
              module: module(),
              initial_step: atom(),
              context: map(),
              subscriber: pid() | nil
            }

      defstruct [:module, :initial_step, subscriber: nil, context: %{}]
    end

    defmodule State do
      @moduledoc false

      @type t :: %__MODULE__{
              config: Config.t(),
              current_step: atom() | nil,
              context: map(),
              status: :running | :complete
            }

      defstruct [:config, :current_step, context: %{}, status: :running]
    end

    # Client API

    @doc """
    Starts an `IVRRunner` GenServer linked to the calling process.

    ## Options

    - `:module` — The IVR workflow behaviour module (required).
    - `:initial_step` — The first step atom to execute (required).
    - `:context` — Initial context map. Default: `%{}`.
    - `:subscriber` — PID to receive `{:ivr_action, action}` and `{:ivr_complete, reason}` messages.
    """
    @spec start_link(keyword()) :: GenServer.on_start()
    def start_link(opts) when is_list(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    @doc """
    Advances the workflow to the next step with updated context.

    Merges `new_context` into the current context and triggers the next step.
    """
    @spec advance(pid(), map()) :: :ok
    def advance(pid, new_context \\ %{}) when is_map(new_context) do
      GenServer.cast(pid, {:advance, new_context})
    end

    @doc """
    Signals that the current step has timed out waiting for input.

    Calls the workflow module's `on_timeout/2` callback.
    """
    @spec timeout(pid()) :: :ok
    def timeout(pid) do
      GenServer.cast(pid, :timeout)
    end

    @doc """
    Returns the current workflow state (step and context).
    """
    @spec get_state(pid()) :: map()
    def get_state(pid) do
      GenServer.call(pid, :get_state, 5_000)
    end

    @doc """
    Stops the IVRRunner GenServer.
    """
    @spec stop(pid()) :: :ok
    def stop(pid) do
      GenServer.stop(pid, :normal, 5_000)
    end

    # GenServer Callbacks

    @impl true
    def init(opts) do
      mod = Keyword.fetch!(opts, :module)
      initial_step = Keyword.fetch!(opts, :initial_step)
      context = Keyword.get(opts, :context, %{})
      subscriber = Keyword.get(opts, :subscriber)

      config = %Config{
        module: mod,
        initial_step: initial_step,
        context: context,
        subscriber: subscriber
      }

      state = %State{
        config: config,
        current_step: initial_step,
        context: context,
        status: :running
      }

      # Execute the first step immediately
      {:ok, state, {:continue, :execute_step}}
    end

    @impl true
    def handle_continue(:execute_step, %State{status: :running} = state) do
      action = state.config.module.handle_step(state.current_step, state.context)
      state = process_action(action, state)
      {:noreply, state}
    end

    def handle_continue(:execute_step, %State{} = state) do
      {:noreply, state}
    end

    @impl true
    def handle_cast({:advance, new_context}, %State{status: :running} = state) do
      merged_context = Map.merge(state.context, new_context)
      state = %{state | context: merged_context}
      action = state.config.module.handle_step(state.current_step, merged_context)
      state = process_action(action, state)
      {:noreply, state}
    end

    def handle_cast({:advance, _new_context}, %State{} = state) do
      Logger.debug("IVRRunner: ignoring advance — workflow already complete")
      {:noreply, state}
    end

    @impl true
    def handle_cast(:timeout, %State{status: :running} = state) do
      action = state.config.module.on_timeout(state.current_step, state.context)
      state = process_action(action, state)
      {:noreply, state}
    end

    def handle_cast(:timeout, %State{} = state) do
      {:noreply, state}
    end

    @impl true
    def handle_call(:get_state, _from, %State{} = state) do
      result = %{
        current_step: state.current_step,
        context: state.context,
        status: state.status
      }

      {:reply, result, state}
    end

    # Private Helpers

    @spec process_action(term(), State.t()) :: State.t()
    defp process_action({:speak, text}, state) do
      notify_subscriber(state.config.subscriber, {:ivr_action, {:speak, text}})
      complete_workflow(:completed, state)
    end

    defp process_action({:speak, text, opts}, state) when is_list(opts) do
      notify_subscriber(state.config.subscriber, {:ivr_action, {:speak, text}})

      case Keyword.get(opts, :next) do
        nil ->
          complete_workflow(:completed, state)

        next_step ->
          %{state | current_step: next_step}
      end
    end

    defp process_action({:collect_digits, opts}, state) do
      notify_subscriber(state.config.subscriber, {:ivr_action, {:collect_digits, opts}})
      state
    end

    defp process_action({:collect_speech, opts}, state) do
      notify_subscriber(state.config.subscriber, {:ivr_action, {:collect_speech, opts}})
      state
    end

    defp process_action({:transfer, phone_number}, state) do
      notify_subscriber(state.config.subscriber, {:ivr_action, {:transfer, phone_number}})
      complete_workflow(:transferred, state)
    end

    defp process_action({:hangup, reason}, state) do
      notify_subscriber(state.config.subscriber, {:ivr_action, {:hangup, reason}})
      complete_workflow(:hung_up, state)
    end

    defp process_action(:done, state) do
      complete_workflow(:completed, state)
    end

    defp process_action(unknown, state) do
      Logger.warning("IVRRunner: unknown action #{inspect(unknown)}")
      state
    end

    @spec complete_workflow(atom(), State.t()) :: State.t()
    defp complete_workflow(reason, state) do
      state.config.module.on_complete(reason, state.context)
      notify_subscriber(state.config.subscriber, {:ivr_complete, reason})
      %{state | status: :complete}
    end

    @spec notify_subscriber(pid() | nil, term()) :: :ok
    defp notify_subscriber(nil, _message), do: :ok
    defp notify_subscriber(pid, message) when is_pid(pid), do: send(pid, message)
  end
end

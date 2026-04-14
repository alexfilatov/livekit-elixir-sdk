defmodule Livekit.Agents.AgentStateMachine do
  @moduledoc """
  GenServer tracking the agent's processing state.

  Valid transitions:
  - `:initializing` -> `:listening` (agent ready)
  - `:listening` -> `:thinking` (LLM processing)
  - `:thinking` -> `:speaking` (TTS playing)
  - `:speaking` -> `:listening` (turn complete)
  - `:thinking` -> `:listening` (interruption)

  Invalid transitions (e.g., `:speaking` -> `:thinking`) are logged as warnings
  and ignored — no state change or event published.

  On every valid transition, a `%Livekit.Agents.Events.AgentStateChanged{}` event is
  published via `EventBus.publish/2` when a `session_id` is configured.
  """

  use GenServer
  require Logger

  alias Livekit.Agents.{EventBus, Events}

  # ---------------------------------------------------------------------------
  # Config struct
  # ---------------------------------------------------------------------------

  defmodule Config do
    @moduledoc "Configuration for `Livekit.Agents.AgentStateMachine`."

    @type t :: %__MODULE__{
            session_id: String.t() | nil
          }

    defstruct session_id: nil
  end

  # ---------------------------------------------------------------------------
  # State struct
  # ---------------------------------------------------------------------------

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            config: Config.t(),
            status: :initializing | :listening | :thinking | :speaking,
            metrics: map()
          }

    defstruct [
      :config,
      status: :initializing,
      metrics: %{
        transitions: 0
      }
    ]
  end

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @doc """
  Starts an `AgentStateMachine` GenServer linked to the calling process.

  ## Options

  - `:session_id` — EventBus session ID for publishing state change events.
    Defaults to `nil` (no events published).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    config = %Config{
      session_id: Keyword.get(opts, :session_id)
    }

    GenServer.start_link(__MODULE__, config)
  end

  @doc """
  Requests a state transition to the given state.

  Invalid transitions are silently ignored (with a warning log). Valid
  `new_state` values are `:listening`, `:thinking`, and `:speaking`.
  """
  @spec set_state(pid(), :listening | :thinking | :speaking) :: :ok
  def set_state(pid, new_state), do: GenServer.cast(pid, {:set_state, new_state})

  @doc """
  Returns the current state of the agent state machine.
  """
  @spec get_state(pid()) :: :initializing | :listening | :thinking | :speaking
  def get_state(pid), do: GenServer.call(pid, :get_state, 5_000)

  @doc """
  Returns the current metrics map.
  """
  @spec get_metrics(pid()) :: map()
  def get_metrics(pid), do: GenServer.call(pid, :get_metrics, 5_000)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%Config{} = config) do
    {:ok, %State{config: config}}
  end

  @impl true
  def handle_cast({:set_state, new_state}, %State{status: current} = state) do
    if valid_transition?(current, new_state) do
      {:noreply, transition(state, new_state)}
    else
      Logger.warning("AgentStateMachine: invalid transition #{current} -> #{new_state}, ignoring")

      {:noreply, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, %State{} = state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, %State{} = state) do
    {:reply, state.metrics, state}
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  @spec valid_transition?(
          :initializing | :listening | :thinking | :speaking,
          :listening | :thinking | :speaking
        ) :: boolean()
  defp valid_transition?(:initializing, :listening), do: true
  defp valid_transition?(:listening, :thinking), do: true
  defp valid_transition?(:thinking, :speaking), do: true
  defp valid_transition?(:speaking, :listening), do: true
  defp valid_transition?(:thinking, :listening), do: true
  defp valid_transition?(_from, _to), do: false

  @spec transition(State.t(), :listening | :thinking | :speaking) :: State.t()
  defp transition(%State{status: from} = state, to) do
    Logger.debug("AgentStateMachine: #{from} -> #{to}")

    event = %Events.AgentStateChanged{
      from: from,
      to: to,
      timestamp: DateTime.utc_now()
    }

    maybe_publish(state.config.session_id, event)

    metrics = Map.update!(state.metrics, :transitions, &(&1 + 1))

    %{state | status: to, metrics: metrics}
  end

  @spec maybe_publish(String.t() | nil, struct()) :: :ok
  defp maybe_publish(nil, _event), do: :ok
  defp maybe_publish(session_id, event), do: EventBus.publish(session_id, event)
end

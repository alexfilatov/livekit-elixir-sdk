defmodule Livekit.Agents.UserStateMachine do
  @moduledoc """
  GenServer tracking the user's voice activity state.

  Transitions:
  - `:listening` -> `:speaking` when `speech_start/1` is called
  - `:speaking` -> `:listening` when `speech_end/1` is called
  - `:speaking` -> `:away` when the configurable away timeout elapses with no `speech_end`
  - `:away` -> `:speaking` when `speech_start/1` is called

  On every valid transition, a `%Livekit.Agents.Events.UserStateChanged{}` event is
  published via `EventBus.publish/2` when an `event_bus` session id is configured.
  """

  use GenServer
  require Logger

  alias Livekit.Agents.{EventBus, Events}

  # ---------------------------------------------------------------------------
  # Config struct
  # ---------------------------------------------------------------------------

  defmodule Config do
    @moduledoc "Configuration for `Livekit.Agents.UserStateMachine`."

    @type t :: %__MODULE__{
            away_timeout_ms: pos_integer(),
            session_id: String.t() | nil
          }

    defstruct away_timeout_ms: 30_000,
              session_id: nil
  end

  # ---------------------------------------------------------------------------
  # State struct
  # ---------------------------------------------------------------------------

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            config: Config.t(),
            status: :listening | :speaking | :away,
            away_timer: reference() | nil,
            metrics: map()
          }

    defstruct [
      :config,
      :away_timer,
      status: :listening,
      metrics: %{
        transitions: 0,
        speaking_count: 0,
        away_count: 0
      }
    ]
  end

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @doc """
  Starts a `UserStateMachine` GenServer linked to the calling process.

  ## Options

  - `:away_timeout_ms` — milliseconds of speaking with no `speech_end` before
    transitioning to `:away`. Defaults to `30_000`.
  - `:session_id` — EventBus session ID for publishing state change events.
    Defaults to `nil` (no events published).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    config = %Config{
      away_timeout_ms: Keyword.get(opts, :away_timeout_ms, 30_000),
      session_id: Keyword.get(opts, :session_id)
    }

    GenServer.start_link(__MODULE__, config)
  end

  @doc """
  Signals that the user has started speaking. Transitions `:listening` or
  `:away` -> `:speaking`.
  """
  @spec speech_start(pid()) :: :ok
  def speech_start(pid), do: GenServer.cast(pid, :speech_start)

  @doc """
  Signals that the user has stopped speaking. Transitions `:speaking` ->
  `:listening` and starts the away timeout timer.
  """
  @spec speech_end(pid()) :: :ok
  def speech_end(pid), do: GenServer.cast(pid, :speech_end)

  @doc """
  Returns the current state of the user state machine.
  """
  @spec get_state(pid()) :: :listening | :speaking | :away
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
  def handle_cast(:speech_start, %State{status: status} = state)
      when status in [:listening, :away] do
    state = cancel_away_timer(state)
    state = transition(state, :speaking)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:speech_start, %State{status: :speaking} = state) do
    # Already speaking — no-op
    {:noreply, state}
  end

  @impl true
  def handle_cast(:speech_end, %State{status: :speaking} = state) do
    state = transition(state, :listening)
    timer_ref = Process.send_after(self(), :away_timeout, state.config.away_timeout_ms)
    {:noreply, %{state | away_timer: timer_ref}}
  end

  @impl true
  def handle_cast(:speech_end, %State{} = state) do
    # Not speaking — no-op
    {:noreply, state}
  end

  @impl true
  def handle_info(:away_timeout, %State{status: :listening} = state) do
    state = transition(state, :away)
    {:noreply, %{state | away_timer: nil}}
  end

  @impl true
  def handle_info(:away_timeout, %State{} = state) do
    # Timer fired in unexpected state (e.g., user started speaking again) — ignore
    {:noreply, %{state | away_timer: nil}}
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

  @spec transition(State.t(), :listening | :speaking | :away) :: State.t()
  defp transition(%State{status: from} = state, to) do
    Logger.debug("UserStateMachine: #{from} -> #{to}")

    event = %Events.UserStateChanged{
      from: from,
      to: to,
      timestamp: DateTime.utc_now()
    }

    maybe_publish(state.config.session_id, event)

    metrics =
      state.metrics
      |> Map.update!(:transitions, &(&1 + 1))
      |> update_state_count(to)

    %{state | status: to, metrics: metrics}
  end

  @spec update_state_count(map(), atom()) :: map()
  defp update_state_count(metrics, :speaking),
    do: Map.update!(metrics, :speaking_count, &(&1 + 1))

  defp update_state_count(metrics, :away), do: Map.update!(metrics, :away_count, &(&1 + 1))
  defp update_state_count(metrics, _), do: metrics

  @spec cancel_away_timer(State.t()) :: State.t()
  defp cancel_away_timer(%State{away_timer: nil} = state), do: state

  defp cancel_away_timer(%State{away_timer: timer_ref} = state) do
    Process.cancel_timer(timer_ref)
    %{state | away_timer: nil}
  end

  @spec maybe_publish(String.t() | nil, struct()) :: :ok
  defp maybe_publish(nil, _event), do: :ok
  defp maybe_publish(session_id, event), do: EventBus.publish(session_id, event)
end

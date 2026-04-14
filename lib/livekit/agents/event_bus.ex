defmodule Livekit.Agents.EventBus do
  @moduledoc """
  Registry-based pub/sub event bus for LiveKit Agents.

  Processes subscribe by calling `subscribe/1` with a session_id string, and
  receive all published events as `{:livekit_event, event}` messages. Unsubscribe
  via `unsubscribe/1`.

  EventBus also bridges `:telemetry` pipeline events into the pub/sub stream,
  publishing `%Events.TelemetryMeasurement{}` structs for TTFT, end-to-end
  latency, and token counts.

  ## Usage

      {:ok, _} = EventBus.start_link()
      EventBus.subscribe("session-1")
      EventBus.publish("session-1", %Events.UserStateChanged{...})
      # current process receives: {:livekit_event, %Events.UserStateChanged{...}}
  """

  alias Livekit.Agents.Events

  @registry Livekit.Agents.EventBus.Registry
  @telemetry_handler_id "livekit-event-bus"

  @telemetry_events [
    [:livekit, :agents, :pipeline, :stt_complete],
    [:livekit, :agents, :pipeline, :llm_first_token],
    [:livekit, :agents, :pipeline, :tts_start]
  ]

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the EventBus Registry and attaches `:telemetry` handlers for pipeline
  events.

  Returns `{:ok, pid}` where `pid` is the Registry process.

  Note: The Registry is started standalone so it can be used in tests without
  a Supervisor. Phase 9 (Worker Infrastructure) will add it to the OTP
  supervision tree.
  """
  @spec start_link() :: {:ok, pid()} | {:error, term()}
  def start_link do
    result = Registry.start_link(keys: :duplicate, name: @registry)

    :telemetry.attach_many(
      @telemetry_handler_id,
      @telemetry_events,
      &__MODULE__.handle_telemetry_event/4,
      nil
    )

    result
  end

  @doc """
  Subscribes the calling process to all events published under `session_id`.

  The calling process will receive messages of the form `{:livekit_event, event}`
  for every event published to this session.
  """
  @spec subscribe(session_id :: String.t()) :: {:ok, term()} | {:error, term()}
  def subscribe(session_id) do
    # ISSUE-15: Handle Registry not started gracefully
    try do
      Registry.register(@registry, session_id, self())
    catch
      :exit, _ -> {:error, :not_started}
    end
  end

  @doc """
  Unsubscribes the calling process from `session_id`.
  """
  @spec unsubscribe(session_id :: String.t()) :: :ok
  def unsubscribe(session_id) do
    Registry.unregister(@registry, session_id)
  end

  @doc """
  Publishes `event` to all processes subscribed to `session_id`.

  Each subscriber receives `{:livekit_event, event}` as a message.
  """
  @spec publish(session_id :: String.t(), event :: struct()) :: :ok
  def publish(session_id, event) do
    Registry.dispatch(@registry, session_id, fn entries ->
      for {pid, _value} <- entries, do: send(pid, {:livekit_event, event})
    end)

    :ok
  end

  @doc """
  Convenience function for emitting a `TelemetryMeasurement` event manually.

  Useful for state machines or other components to report metrics directly
  into the pub/sub stream.
  """
  @spec emit_metric(session_id :: String.t(), metric :: atom(), value :: number()) :: :ok
  def emit_metric(session_id, metric, value) do
    event = %Events.TelemetryMeasurement{
      metric: metric,
      value: value,
      metadata: %{},
      timestamp: DateTime.utc_now()
    }

    publish(session_id, event)
  end

  @doc """
  Detaches the `:telemetry` handlers attached by `start_link/0`.
  """
  @spec stop() :: :ok
  def stop do
    :telemetry.detach(@telemetry_handler_id)

    # ISSUE-26: Also stop the Registry process if it is running
    case Process.whereis(@registry) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal, 5_000)
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Telemetry handler (must be a named function, not a closure)
  # ---------------------------------------------------------------------------

  @doc false
  @spec handle_telemetry_event(
          [atom()],
          map(),
          map(),
          term()
        ) :: :ok
  def handle_telemetry_event(
        [:livekit, :agents, :pipeline, :stt_complete] = _event_name,
        measurements,
        metadata,
        _config
      ) do
    # ISSUE-20: stt_complete should emit :stt_latency_ms, not :ttft_ms
    value = Map.get(measurements, :monotonic_time, System.monotonic_time(:millisecond))

    emit_to_session(
      %Events.TelemetryMeasurement{
        metric: :stt_latency_ms,
        value: System.convert_time_unit(value, :native, :millisecond),
        metadata: metadata,
        timestamp: DateTime.utc_now()
      },
      metadata
    )
  end

  def handle_telemetry_event(
        [:livekit, :agents, :pipeline, :llm_first_token] = _event_name,
        measurements,
        metadata,
        _config
      ) do
    value = Map.get(measurements, :monotonic_time, System.monotonic_time(:millisecond))

    emit_to_session(
      %Events.TelemetryMeasurement{
        metric: :ttft_ms,
        value: System.convert_time_unit(value, :native, :millisecond),
        metadata: metadata,
        timestamp: DateTime.utc_now()
      },
      metadata
    )
  end

  def handle_telemetry_event(
        [:livekit, :agents, :pipeline, :tts_start] = _event_name,
        measurements,
        metadata,
        _config
      ) do
    value = Map.get(measurements, :monotonic_time, System.monotonic_time(:millisecond))
    bytes = Map.get(measurements, :bytes, 0)

    emit_to_session(
      %Events.TelemetryMeasurement{
        metric: :end_to_end_latency_ms,
        value: System.convert_time_unit(value, :native, :millisecond),
        metadata: Map.put(metadata, :bytes, bytes),
        timestamp: DateTime.utc_now()
      },
      metadata
    )
  end

  def handle_telemetry_event(_event_name, _measurements, _metadata, _config), do: :ok

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  # Dispatches a telemetry measurement only to subscribers of the session that
  # emitted the event (identified by the :session_id key in telemetry metadata).
  # Falls back to broadcasting to all sessions when no session_id is present,
  # preserving backwards-compatible behaviour for callers that don't set it yet.
  @spec emit_to_session(Events.TelemetryMeasurement.t(), map()) :: :ok
  defp emit_to_session(event, %{session_id: session_id}) when is_binary(session_id) do
    publish(session_id, event)
  end

  defp emit_to_session(event, _metadata) do
    emit_to_all_sessions(event)
  end

  # Broadcasts a telemetry measurement to all currently registered session subscribers.
  @spec emit_to_all_sessions(Events.TelemetryMeasurement.t()) :: :ok
  defp emit_to_all_sessions(event) do
    # Select all {key, pid, value} entries from the Registry
    entries = Registry.select(@registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])

    for {_session_id, pid} <- entries do
      send(pid, {:livekit_event, event})
    end

    :ok
  end
end

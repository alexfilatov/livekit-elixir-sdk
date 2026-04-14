defmodule Livekit.Agents.EventBusTest do
  # async: false because the Registry is globally named — shared across all tests
  use ExUnit.Case, async: false

  alias Livekit.Agents.{EventBus, Events}
  alias Events.{TelemetryMeasurement, UserStateChanged}

  setup do
    # Start the EventBus Registry under a temporary supervisor so it outlives
    # each individual test process (which would kill a linked Registry on exit).
    pid =
      case EventBus.start_link() do
        {:ok, p} ->
          p

        {:error, {:already_started, p}} ->
          p
      end

    # Unlink so test process exit doesn't kill the Registry
    Process.unlink(pid)

    # Use unique session_id per test to avoid cross-test interference
    session_id = "test-#{:erlang.unique_integer([:positive])}"
    %{session_id: session_id}
  end

  describe "subscribe and publish" do
    test "subscriber receives {:livekit_event, event}", %{session_id: session_id} do
      EventBus.subscribe(session_id)
      event = %UserStateChanged{from: :listening, to: :speaking, timestamp: DateTime.utc_now()}
      EventBus.publish(session_id, event)
      assert_receive {:livekit_event, %UserStateChanged{from: :listening, to: :speaking}}, 500
      EventBus.unsubscribe(session_id)
    end

    test "multiple subscribers on same session_id all receive the event", %{
      session_id: session_id
    } do
      parent = self()

      # Spawn a second subscriber process
      subscriber2 =
        spawn(fn ->
          EventBus.subscribe(session_id)
          send(parent, :ready)

          receive do
            {:livekit_event, event} -> send(parent, {:received, event})
          after
            1000 -> send(parent, :timeout)
          end
        end)

      assert_receive :ready, 500

      # Also subscribe the current process
      EventBus.subscribe(session_id)

      event = %UserStateChanged{from: :speaking, to: :listening, timestamp: DateTime.utc_now()}
      EventBus.publish(session_id, event)

      # Both should receive the event
      assert_receive {:livekit_event, %UserStateChanged{}}, 500
      assert_receive {:received, %UserStateChanged{}}, 500

      EventBus.unsubscribe(session_id)
      Process.exit(subscriber2, :kill)
    end
  end

  describe "unsubscribe" do
    test "stops delivery after unsubscribe", %{session_id: session_id} do
      EventBus.subscribe(session_id)

      # First publish — should arrive
      event1 = %UserStateChanged{from: :listening, to: :speaking, timestamp: DateTime.utc_now()}
      EventBus.publish(session_id, event1)
      assert_receive {:livekit_event, %UserStateChanged{}}, 500

      # Unsubscribe
      EventBus.unsubscribe(session_id)

      # Second publish — should NOT arrive
      event2 = %UserStateChanged{from: :speaking, to: :listening, timestamp: DateTime.utc_now()}
      EventBus.publish(session_id, event2)
      refute_receive {:livekit_event, _}, 100
    end
  end

  describe "emit_metric" do
    test "publishes TelemetryMeasurement to subscribers", %{session_id: session_id} do
      EventBus.subscribe(session_id)
      EventBus.emit_metric(session_id, :ttft_ms, 123)

      assert_receive {:livekit_event, %TelemetryMeasurement{metric: :ttft_ms, value: 123}}, 500
      EventBus.unsubscribe(session_id)
    end

    test "TelemetryMeasurement has expected fields", %{session_id: session_id} do
      EventBus.subscribe(session_id)
      EventBus.emit_metric(session_id, :token_count, 42)

      assert_receive {:livekit_event, measurement}, 500
      assert %TelemetryMeasurement{} = measurement
      assert measurement.metric == :token_count
      assert measurement.value == 42
      assert is_map(measurement.metadata)
      assert %DateTime{} = measurement.timestamp
      EventBus.unsubscribe(session_id)
    end
  end

  describe "publish with no subscribers" do
    test "is a no-op and does not crash", %{session_id: session_id} do
      unregistered_id = "unregistered-#{:erlang.unique_integer([:positive])}"
      event = %UserStateChanged{from: :listening, to: :speaking, timestamp: DateTime.utc_now()}
      # Should not raise or crash
      assert :ok = EventBus.publish(unregistered_id, event)
      # session_id is unused here — this tests the no-subscriber case
      refute_receive {:livekit_event, _}, 50
      _ = session_id
    end
  end

  describe "telemetry bridge" do
    test "llm_first_token event publishes TelemetryMeasurement to all subscribers", %{
      session_id: session_id
    } do
      EventBus.subscribe(session_id)

      :telemetry.execute(
        [:livekit, :agents, :pipeline, :llm_first_token],
        %{monotonic_time: System.monotonic_time()},
        %{role: :assistant}
      )

      assert_receive {:livekit_event, %TelemetryMeasurement{metric: :ttft_ms}}, 500
      EventBus.unsubscribe(session_id)
    end

    test "stt_complete event publishes TelemetryMeasurement", %{session_id: session_id} do
      EventBus.subscribe(session_id)

      :telemetry.execute(
        [:livekit, :agents, :pipeline, :stt_complete],
        %{monotonic_time: System.monotonic_time()},
        %{}
      )

      assert_receive {:livekit_event, %TelemetryMeasurement{metric: :stt_latency_ms}}, 500
      EventBus.unsubscribe(session_id)
    end

    test "tts_start event publishes end_to_end_latency_ms measurement", %{
      session_id: session_id
    } do
      EventBus.subscribe(session_id)

      :telemetry.execute(
        [:livekit, :agents, :pipeline, :tts_start],
        %{monotonic_time: System.monotonic_time(), bytes: 1024},
        %{}
      )

      assert_receive {:livekit_event, %TelemetryMeasurement{metric: :end_to_end_latency_ms}},
                     500

      EventBus.unsubscribe(session_id)
    end
  end
end

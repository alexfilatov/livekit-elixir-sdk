defmodule Livekit.Agents.UserStateMachineTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.{EventBus, Events, UserStateMachine}
  alias Livekit.Agents.Events.UserStateChanged

  # Start the EventBus Registry before any test that needs it (idempotent).
  defp ensure_event_bus do
    # Started once in test_helper.exs and deliberately unlinked, so a test
    # finishing cannot take the event bus down with it.
    case Process.whereis(Livekit.Agents.EventBus.Registry) do
      nil -> flunk("EventBus not running — test_helper.exs should have started it")
      _pid -> :ok
    end
  end

  describe "initial state" do
    test "starts in :listening state" do
      {:ok, pid} = UserStateMachine.start_link()
      assert UserStateMachine.get_state(pid) == :listening
    end
  end

  describe "speech_start" do
    test "transitions :listening -> :speaking" do
      {:ok, pid} = UserStateMachine.start_link()
      UserStateMachine.speech_start(pid)
      assert UserStateMachine.get_state(pid) == :speaking
    end

    test "transitions :away -> :speaking" do
      # Use a tiny timeout so the away timer fires quickly
      {:ok, pid} = UserStateMachine.start_link(away_timeout_ms: 50)
      UserStateMachine.speech_start(pid)
      UserStateMachine.speech_end(pid)
      # Wait for away timer to fire (:listening -> :away)
      Process.sleep(120)
      assert UserStateMachine.get_state(pid) == :away

      UserStateMachine.speech_start(pid)
      assert UserStateMachine.get_state(pid) == :speaking
    end

    test "is a no-op when already :speaking" do
      {:ok, pid} = UserStateMachine.start_link()
      UserStateMachine.speech_start(pid)
      UserStateMachine.speech_start(pid)
      assert UserStateMachine.get_state(pid) == :speaking
    end
  end

  describe "speech_end" do
    test "transitions :speaking -> :listening" do
      {:ok, pid} = UserStateMachine.start_link()
      UserStateMachine.speech_start(pid)
      UserStateMachine.speech_end(pid)
      assert UserStateMachine.get_state(pid) == :listening
    end

    test "away timer elapses -> transitions :listening -> :away" do
      {:ok, pid} = UserStateMachine.start_link(away_timeout_ms: 50)
      UserStateMachine.speech_start(pid)
      UserStateMachine.speech_end(pid)
      # :listening now; wait for away timer
      Process.sleep(120)
      assert UserStateMachine.get_state(pid) == :away
    end

    test "speech_start during :speaking cancels pending away timer" do
      {:ok, pid} = UserStateMachine.start_link(away_timeout_ms: 50)
      UserStateMachine.speech_start(pid)
      UserStateMachine.speech_end(pid)
      # Immediately start speaking again before the away timer can fire
      UserStateMachine.speech_start(pid)
      # Wait longer than away_timeout_ms to confirm no :away transition occurs
      Process.sleep(120)
      assert UserStateMachine.get_state(pid) == :speaking
    end

    test "is a no-op when not :speaking" do
      {:ok, pid} = UserStateMachine.start_link()
      # Still :listening, speech_end should be a no-op
      UserStateMachine.speech_end(pid)
      assert UserStateMachine.get_state(pid) == :listening
    end
  end

  describe "get_metrics" do
    test "returns a map with :transitions key" do
      {:ok, pid} = UserStateMachine.start_link()
      metrics = UserStateMachine.get_metrics(pid)
      assert is_map(metrics)
      assert Map.has_key?(metrics, :transitions)
    end

    test "transition count increments on each valid transition" do
      {:ok, pid} = UserStateMachine.start_link()
      UserStateMachine.speech_start(pid)
      UserStateMachine.speech_end(pid)
      metrics = UserStateMachine.get_metrics(pid)
      assert metrics.transitions == 2
    end
  end

  describe "event_bus integration" do
    test "UserStateChanged is published on each transition" do
      ensure_event_bus()
      session_id = "user-sm-test-#{:erlang.unique_integer([:positive])}"
      EventBus.subscribe(session_id)

      {:ok, pid} = UserStateMachine.start_link(session_id: session_id)
      UserStateMachine.speech_start(pid)

      assert_receive {:livekit_event, %UserStateChanged{from: :listening, to: :speaking}}, 500

      UserStateMachine.speech_end(pid)

      assert_receive {:livekit_event, %UserStateChanged{from: :speaking, to: :listening}}, 500

      EventBus.unsubscribe(session_id)
    end

    test "no events published when session_id is nil" do
      ensure_event_bus()
      # Start without a session_id — no events should arrive
      {:ok, pid} = UserStateMachine.start_link()
      UserStateMachine.speech_start(pid)
      # Nothing should arrive since no session_id configured
      refute_receive {:livekit_event, _}, 100
    end
  end
end

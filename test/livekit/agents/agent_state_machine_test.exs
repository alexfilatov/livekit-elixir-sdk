defmodule Livekit.Agents.AgentStateMachineTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.{AgentStateMachine, EventBus, Events}
  alias Events.AgentStateChanged

  defp ensure_event_bus do
    case EventBus.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  describe "initial state" do
    test "starts in :initializing state" do
      {:ok, pid} = AgentStateMachine.start_link()
      assert AgentStateMachine.get_state(pid) == :initializing
    end
  end

  describe "valid transitions" do
    test ":initializing -> :listening" do
      {:ok, pid} = AgentStateMachine.start_link()
      AgentStateMachine.set_state(pid, :listening)
      assert AgentStateMachine.get_state(pid) == :listening
    end

    test ":listening -> :thinking" do
      {:ok, pid} = AgentStateMachine.start_link()
      AgentStateMachine.set_state(pid, :listening)
      AgentStateMachine.set_state(pid, :thinking)
      assert AgentStateMachine.get_state(pid) == :thinking
    end

    test ":thinking -> :speaking" do
      {:ok, pid} = AgentStateMachine.start_link()
      AgentStateMachine.set_state(pid, :listening)
      AgentStateMachine.set_state(pid, :thinking)
      AgentStateMachine.set_state(pid, :speaking)
      assert AgentStateMachine.get_state(pid) == :speaking
    end

    test ":speaking -> :listening (turn complete)" do
      {:ok, pid} = AgentStateMachine.start_link()
      AgentStateMachine.set_state(pid, :listening)
      AgentStateMachine.set_state(pid, :thinking)
      AgentStateMachine.set_state(pid, :speaking)
      AgentStateMachine.set_state(pid, :listening)
      assert AgentStateMachine.get_state(pid) == :listening
    end

    test ":thinking -> :listening (interruption)" do
      {:ok, pid} = AgentStateMachine.start_link()
      AgentStateMachine.set_state(pid, :listening)
      AgentStateMachine.set_state(pid, :thinking)
      AgentStateMachine.set_state(pid, :listening)
      assert AgentStateMachine.get_state(pid) == :listening
    end
  end

  describe "invalid transitions" do
    test ":speaking -> :speaking is rejected; state stays :speaking" do
      {:ok, pid} = AgentStateMachine.start_link()
      AgentStateMachine.set_state(pid, :listening)
      AgentStateMachine.set_state(pid, :thinking)
      AgentStateMachine.set_state(pid, :speaking)

      # Attempt invalid transition: :speaking -> :speaking
      AgentStateMachine.set_state(pid, :speaking)
      # Allow the GenServer to process the cast
      Process.sleep(50)
      assert AgentStateMachine.get_state(pid) == :speaking
    end

    test ":initializing -> :thinking is rejected" do
      {:ok, pid} = AgentStateMachine.start_link()
      AgentStateMachine.set_state(pid, :thinking)
      Process.sleep(50)
      assert AgentStateMachine.get_state(pid) == :initializing
    end

    test ":initializing -> :speaking is rejected" do
      {:ok, pid} = AgentStateMachine.start_link()
      AgentStateMachine.set_state(pid, :speaking)
      Process.sleep(50)
      assert AgentStateMachine.get_state(pid) == :initializing
    end

    test ":speaking -> :thinking is rejected" do
      {:ok, pid} = AgentStateMachine.start_link()
      AgentStateMachine.set_state(pid, :listening)
      AgentStateMachine.set_state(pid, :thinking)
      AgentStateMachine.set_state(pid, :speaking)
      AgentStateMachine.set_state(pid, :thinking)
      Process.sleep(50)
      assert AgentStateMachine.get_state(pid) == :speaking
    end
  end

  describe "get_metrics" do
    test "returns a map with :transitions key" do
      {:ok, pid} = AgentStateMachine.start_link()
      metrics = AgentStateMachine.get_metrics(pid)
      assert is_map(metrics)
      assert Map.has_key?(metrics, :transitions)
    end

    test "transition count increments on each valid transition" do
      {:ok, pid} = AgentStateMachine.start_link()
      AgentStateMachine.set_state(pid, :listening)
      AgentStateMachine.set_state(pid, :thinking)
      metrics = AgentStateMachine.get_metrics(pid)
      assert metrics.transitions == 2
    end

    test "invalid transitions do not increment transition count" do
      {:ok, pid} = AgentStateMachine.start_link()
      # One valid transition
      AgentStateMachine.set_state(pid, :listening)
      # One invalid transition (rejected)
      AgentStateMachine.set_state(pid, :speaking)
      Process.sleep(50)
      metrics = AgentStateMachine.get_metrics(pid)
      assert metrics.transitions == 1
    end
  end

  describe "event_bus integration" do
    test "AgentStateChanged is published on each valid transition" do
      ensure_event_bus()
      session_id = "agent-sm-test-#{:erlang.unique_integer([:positive])}"
      EventBus.subscribe(session_id)

      {:ok, pid} = AgentStateMachine.start_link(session_id: session_id)
      AgentStateMachine.set_state(pid, :listening)

      assert_receive {:livekit_event, %AgentStateChanged{from: :initializing, to: :listening}},
                     500

      AgentStateMachine.set_state(pid, :thinking)

      assert_receive {:livekit_event, %AgentStateChanged{from: :listening, to: :thinking}}, 500

      EventBus.unsubscribe(session_id)
    end

    test "no events published on invalid transition" do
      ensure_event_bus()
      session_id = "agent-sm-invalid-#{:erlang.unique_integer([:positive])}"
      EventBus.subscribe(session_id)

      {:ok, pid} = AgentStateMachine.start_link(session_id: session_id)
      # Valid: :initializing -> :listening
      AgentStateMachine.set_state(pid, :listening)
      assert_receive {:livekit_event, %AgentStateChanged{to: :listening}}, 500

      # Invalid: :listening -> :speaking (not in valid_transition? guard)
      AgentStateMachine.set_state(pid, :speaking)
      refute_receive {:livekit_event, %AgentStateChanged{to: :speaking}}, 100

      EventBus.unsubscribe(session_id)
    end
  end
end

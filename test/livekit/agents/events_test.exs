defmodule Livekit.Agents.EventsTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.Events

  alias Events.{
    AgentStateChanged,
    ConversationItemAdded,
    ErrorEvent,
    SpeechCreated,
    TelemetryMeasurement,
    UserStateChanged
  }

  describe "UserStateChanged" do
    test "can be constructed and pattern-matched" do
      ts = DateTime.utc_now()
      event = %UserStateChanged{from: :listening, to: :speaking, timestamp: ts}
      assert %UserStateChanged{from: :listening, to: :speaking, timestamp: ^ts} = event
    end

    test "fields are accessible" do
      event = %UserStateChanged{from: :away, to: :listening, timestamp: DateTime.utc_now()}
      assert event.from == :away
      assert event.to == :listening
      assert %DateTime{} = event.timestamp
    end
  end

  describe "AgentStateChanged" do
    test "can be constructed and pattern-matched" do
      event = %AgentStateChanged{
        from: :initializing,
        to: :listening,
        timestamp: DateTime.utc_now()
      }

      assert %AgentStateChanged{from: :initializing, to: :listening} = event
    end

    test "fields are accessible" do
      event = %AgentStateChanged{from: :thinking, to: :speaking, timestamp: DateTime.utc_now()}
      assert event.from == :thinking
      assert event.to == :speaking
    end
  end

  describe "SpeechCreated" do
    test "text field is accessible" do
      event = %SpeechCreated{text: "hello", confidence: 0.95, timestamp: DateTime.utc_now()}
      assert event.text == "hello"
      assert event.confidence == 0.95
    end

    test "confidence is optional (nil allowed)" do
      event = %SpeechCreated{text: "world", confidence: nil, timestamp: DateTime.utc_now()}
      assert %SpeechCreated{text: "world", confidence: nil} = event
    end
  end

  describe "ConversationItemAdded" do
    test "can be matched on role :user" do
      event = %ConversationItemAdded{role: :user, content: "hi", timestamp: DateTime.utc_now()}
      assert %ConversationItemAdded{role: :user, content: "hi"} = event
    end

    test "can be matched on role :assistant" do
      event = %ConversationItemAdded{
        role: :assistant,
        content: "hello there",
        timestamp: DateTime.utc_now()
      }

      assert %ConversationItemAdded{role: :assistant} = event
      assert event.content == "hello there"
    end
  end

  describe "ErrorEvent" do
    test "matches on stage :stt and reason :timeout" do
      event = %ErrorEvent{stage: :stt, reason: :timeout, timestamp: DateTime.utc_now()}
      assert %ErrorEvent{stage: :stt, reason: :timeout} = event
    end

    test "supports all documented stages" do
      for stage <- [:stt, :llm, :tts, :state_machine, :unknown] do
        event = %ErrorEvent{stage: stage, reason: :test, timestamp: DateTime.utc_now()}
        assert event.stage == stage
      end
    end
  end

  describe "TelemetryMeasurement" do
    test "matches on metric :ttft_ms and value" do
      event = %TelemetryMeasurement{
        metric: :ttft_ms,
        value: 150,
        metadata: %{},
        timestamp: DateTime.utc_now()
      }

      assert %TelemetryMeasurement{metric: :ttft_ms, value: 150} = event
    end

    test "metadata field holds arbitrary map" do
      event = %TelemetryMeasurement{
        metric: :token_count,
        value: 42,
        metadata: %{model: "gpt-4"},
        timestamp: DateTime.utc_now()
      }

      assert event.metadata.model == "gpt-4"
    end
  end
end

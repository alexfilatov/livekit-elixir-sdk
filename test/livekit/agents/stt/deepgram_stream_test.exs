defmodule Livekit.Agents.STT.DeepgramStreamTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.STT.Deepgram
  alias Livekit.Agents.STT.Deepgram.Config
  alias Livekit.Agents.STT.DeepgramStream
  alias Livekit.Agents.STT.SpeechEvent

  @mock_config %Config{mock: true, language: "en-US"}

  # Collects events until :end received or timeout; returns list in arrival order.
  defp collect_events(timeout \\ 500) do
    collect_events([], timeout)
  end

  defp collect_events(acc, timeout) do
    receive do
      {:speech_event, %SpeechEvent{type: :end} = event} ->
        Enum.reverse([event | acc])

      {:speech_event, event} ->
        collect_events([event | acc], timeout)
    after
      timeout -> Enum.reverse(acc)
    end
  end

  describe "mock mode streaming" do
    test "emits :start event" do
      {:ok, _pid} = DeepgramStream.start_link({@mock_config, self()})
      events = collect_events()
      types = Enum.map(events, & &1.type)
      assert :start in types
    end

    test "emits :interim event with text 'Hello'" do
      {:ok, _pid} = DeepgramStream.start_link({@mock_config, self()})
      events = collect_events()
      interim = Enum.find(events, &(&1.type == :interim))
      refute is_nil(interim)
      assert interim.text == "Hello"
    end

    test "emits :final event with non-empty transcript" do
      {:ok, _pid} = DeepgramStream.start_link({@mock_config, self()})
      events = collect_events()
      final = Enum.find(events, &(&1.type == :final))
      refute is_nil(final)
      assert String.length(final.text) > 0
    end

    test "emits :end as last event" do
      {:ok, _pid} = DeepgramStream.start_link({@mock_config, self()})
      events = collect_events()
      refute Enum.empty?(events)
      assert List.last(events).type == :end
    end

    test "events arrive in order: start -> interim -> final -> end" do
      {:ok, _pid} = DeepgramStream.start_link({@mock_config, self()})
      events = collect_events()
      types = Enum.map(events, & &1.type)
      assert types == [:start, :interim, :final, :end]
    end

    test "event language matches config" do
      config = %Config{mock: true, language: "fr"}
      {:ok, _pid} = DeepgramStream.start_link({config, self()})
      events = collect_events()

      events
      |> Enum.reject(&(&1.type in [:start, :end]))
      |> Enum.each(fn event ->
        assert event.language == "fr"
      end)
    end

    test "send_audio/2 does not crash in mock mode" do
      {:ok, pid} = DeepgramStream.start_link({@mock_config, self()})
      # cast is safe even to a dead pid — no error raised
      DeepgramStream.send_audio(pid, <<0, 1, 2, 3>>)
      events = collect_events()
      assert Enum.any?(events, &(&1.type == :end))
    end

    test "finish/1 does not crash when called on mock stream" do
      {:ok, pid} = DeepgramStream.start_link({@mock_config, self()})
      # The mock will have exited by the time we collect events;
      # calling finish on a dead pid should not raise
      events = collect_events()
      DeepgramStream.finish(pid)
      assert Enum.any?(events, &(&1.type == :end))
    end
  end

  describe "Deepgram.stream/1 integration (mock)" do
    test "stream/1 returns {:ok, pid}" do
      assert {:ok, _pid} = Deepgram.stream(@mock_config)
      # drain mailbox
      collect_events()
    end

    test "stream/1 delivers full event sequence to caller" do
      {:ok, _pid} = Deepgram.stream(@mock_config)
      events = collect_events()
      types = Enum.map(events, & &1.type)
      assert :start in types
      assert :final in types
      assert :end in types
    end

    test "stream/1 delivers events in correct order" do
      {:ok, _pid} = Deepgram.stream(@mock_config)
      events = collect_events()
      types = Enum.map(events, & &1.type)
      assert types == [:start, :interim, :final, :end]
    end
  end
end

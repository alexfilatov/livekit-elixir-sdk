defmodule Livekit.Agents.STTTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.STT.SpeechEvent

  defmodule StubSTT do
    use Livekit.Agents.STT

    @impl true
    def transcribe(_audio, _opts) do
      {:ok, %SpeechEvent{type: :final, text: "hello world", confidence: 0.99, language: "en"}}
    end

    @impl true
    def capabilities do
      %{streaming: false, interim_results: false, diarization: false, languages: ["en", "es"]}
    end
  end

  test "StubSTT.transcribe/2 returns {:ok, SpeechEvent}" do
    assert {:ok, event} = StubSTT.transcribe(<<1, 2, 3>>, [])
    assert event.type == :final
    assert event.text == "hello world"
    assert event.confidence == 0.99
    assert event.language == "en"
  end

  test "SpeechEvent defaults are correct" do
    event = %SpeechEvent{}
    assert event.text == ""
    assert event.confidence == 0.0
    assert event.language == "en"
    assert event.type == nil
  end

  test "capabilities/0 returns map with all required STT keys" do
    caps = StubSTT.capabilities()
    assert Map.has_key?(caps, :streaming)
    assert Map.has_key?(caps, :interim_results)
    assert Map.has_key?(caps, :diarization)
    assert Map.has_key?(caps, :languages)
  end

  test "default validate_config/1 returns :ok" do
    assert :ok == StubSTT.validate_config(%{api_key: "test"})
  end

  test "SpeechEvent struct accepts all valid type atoms" do
    assert %SpeechEvent{type: :start}
    assert %SpeechEvent{type: :interim}
    assert %SpeechEvent{type: :final}
    assert %SpeechEvent{type: :end}
  end
end

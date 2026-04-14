defmodule Livekit.Agents.TTSTest do
  use ExUnit.Case, async: true

  defmodule StubTTS do
    use Livekit.Agents.TTS

    @impl true
    def synthesize(_text, _opts) do
      {:ok, <<0, 1, 2, 3>>}
    end

    @impl true
    def capabilities do
      %{streaming: false, voices: ["default"], audio_formats: [:pcm], word_timing: false}
    end
  end

  test "StubTTS.synthesize/2 returns {:ok, binary}" do
    assert {:ok, audio} = StubTTS.synthesize("hello", [])
    assert is_binary(audio)
  end

  test "capabilities/0 returns map with all required TTS keys" do
    caps = StubTTS.capabilities()
    assert Map.has_key?(caps, :streaming)
    assert Map.has_key?(caps, :voices)
    assert Map.has_key?(caps, :audio_formats)
    assert Map.has_key?(caps, :word_timing)
  end

  test "capabilities voices is a list" do
    caps = StubTTS.capabilities()
    assert is_list(caps.voices)
  end

  test "capabilities audio_formats is a list" do
    caps = StubTTS.capabilities()
    assert is_list(caps.audio_formats)
  end

  test "default validate_config/1 returns :ok" do
    assert :ok == StubTTS.validate_config(%{api_key: "test"})
  end
end

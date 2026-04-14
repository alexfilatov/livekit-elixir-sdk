defmodule Livekit.Agents.STT.StreamAdapterTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.STT.StreamAdapter
  alias Livekit.Agents.STT.StreamAdapter.Config
  alias Livekit.Agents.STT.SpeechEvent

  # ---------------------------------------------------------------------------
  # Minimal mock batch STT providers
  # ---------------------------------------------------------------------------

  defmodule BatchProvider do
    use Livekit.Agents.STT

    @impl true
    def transcribe(audio, opts) do
      config = Keyword.get(opts, :config, %{})
      text = Map.get(config, :text, "default transcript")
      language = Map.get(config, :language, "en")

      cond do
        byte_size(audio) == 0 ->
          {:ok, %SpeechEvent{type: :final, text: "", confidence: 0.0, language: language}}

        true ->
          {:ok, %SpeechEvent{type: :final, text: text, confidence: 0.99, language: language}}
      end
    end

    @impl true
    def capabilities do
      %{streaming: false, interim_results: false, diarization: false, languages: ["en"]}
    end
  end

  defmodule ErrorBatchProvider do
    use Livekit.Agents.STT

    @impl true
    def transcribe(_audio, _opts), do: {:error, :transcription_failed}

    @impl true
    def capabilities do
      %{streaming: false, interim_results: false, diarization: false, languages: ["en"]}
    end
  end

  # ---------------------------------------------------------------------------
  # capabilities/0
  # ---------------------------------------------------------------------------

  describe "capabilities/0" do
    test "reports streaming: true" do
      caps = StreamAdapter.capabilities()
      assert caps.streaming == true
    end

    test "returns valid capability map" do
      caps = StreamAdapter.capabilities()
      assert is_boolean(caps.interim_results)
      assert is_boolean(caps.diarization)
      assert is_list(caps.languages)
    end
  end

  # ---------------------------------------------------------------------------
  # validate_config/1
  # ---------------------------------------------------------------------------

  describe "validate_config/1" do
    test "returns error when provider is nil" do
      config = %Config{provider: nil}
      assert {:error, :missing_provider} = StreamAdapter.validate_config(config)
    end

    test "returns :ok when provider is set" do
      config = %Config{provider: {BatchProvider, %{}}}
      assert :ok = StreamAdapter.validate_config(config)
    end
  end

  # ---------------------------------------------------------------------------
  # transcribe/2
  # ---------------------------------------------------------------------------

  describe "transcribe/2" do
    test "delegates to underlying batch provider" do
      config = %Config{provider: {BatchProvider, %{text: "delegated"}}}
      audio = :binary.copy(<<0>>, 100)
      assert {:ok, event} = StreamAdapter.transcribe(audio, config: config)
      assert event.text == "delegated"
      assert event.type == :final
    end

    test "propagates errors from underlying provider" do
      config = %Config{provider: {ErrorBatchProvider, %{}}}
      assert {:error, :transcription_failed} = StreamAdapter.transcribe(<<>>, config: config)
    end
  end

  # ---------------------------------------------------------------------------
  # stream/1 — basic event sequence
  # ---------------------------------------------------------------------------

  describe "stream/1" do
    test "returns {:ok, pid}" do
      config = %Config{provider: {BatchProvider, %{}}}
      assert {:ok, pid} = StreamAdapter.stream(config)
      assert is_pid(pid)
      StreamAdapter.finish(pid)
    end

    test "emits :start, :final, :end events on finish" do
      config = %Config{provider: {BatchProvider, %{text: "hello world"}}}
      {:ok, stream_pid} = StreamAdapter.stream(config)

      audio = :binary.copy(<<0>>, 100)
      send(stream_pid, {:audio_frame, audio})
      StreamAdapter.finish(stream_pid)

      assert_receive {:speech_event, %SpeechEvent{type: :start}}, 1000
      assert_receive {:speech_event, %SpeechEvent{type: :final, text: "hello world"}}, 1000
      assert_receive {:speech_event, %SpeechEvent{type: :end}}, 1000
    end

    test "emits :end event even for empty audio" do
      config = %Config{provider: {BatchProvider, %{}}}
      {:ok, stream_pid} = StreamAdapter.stream(config)
      StreamAdapter.finish(stream_pid)

      assert_receive {:speech_event, %SpeechEvent{type: :start}}, 1000
      assert_receive {:speech_event, %SpeechEvent{type: :end}}, 1000
    end

    test "accumulates multiple audio chunks before transcribing" do
      config = %Config{provider: {BatchProvider, %{text: "accumulated"}}}
      {:ok, stream_pid} = StreamAdapter.stream(config)

      send(stream_pid, {:audio_frame, :binary.copy(<<0>>, 50)})
      send(stream_pid, {:audio_frame, :binary.copy(<<0>>, 50)})
      StreamAdapter.finish(stream_pid)

      assert_receive {:speech_event, %SpeechEvent{type: :start}}, 1000
      assert_receive {:speech_event, %SpeechEvent{type: :final, text: "accumulated"}}, 1000
      assert_receive {:speech_event, %SpeechEvent{type: :end}}, 1000
    end

    test "sends {:error, reason} when provider fails" do
      config = %Config{provider: {ErrorBatchProvider, %{}}}
      {:ok, stream_pid} = StreamAdapter.stream(config)

      send(stream_pid, {:audio_frame, :binary.copy(<<0>>, 100)})
      StreamAdapter.finish(stream_pid)

      assert_receive {:speech_event, %SpeechEvent{type: :start}}, 1000
      assert_receive {:error, :transcription_failed}, 1000
      assert_receive {:speech_event, %SpeechEvent{type: :end}}, 1000
    end
  end

  # ---------------------------------------------------------------------------
  # finish/1
  # ---------------------------------------------------------------------------

  describe "finish/1" do
    test "returns :ok" do
      config = %Config{provider: {BatchProvider, %{}}}
      {:ok, stream_pid} = StreamAdapter.stream(config)
      assert :ok = StreamAdapter.finish(stream_pid)
    end
  end
end

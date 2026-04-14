defmodule Livekit.Agents.TTS.StreamAdapterTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.TTS.StreamAdapter
  alias Livekit.Agents.TTS.StreamAdapter.Config
  alias Livekit.Agents.AudioFrame

  # ---------------------------------------------------------------------------
  # Minimal mock batch TTS providers
  # ---------------------------------------------------------------------------

  defmodule BatchProvider do
    use Livekit.Agents.TTS

    @impl true
    def synthesize(text, opts) do
      config = Keyword.get(opts, :config, %{})
      audio = Map.get(config, :audio, :binary.copy(<<0>>, byte_size(text) * 2))
      {:ok, audio}
    end

    @impl true
    def capabilities do
      %{streaming: false, voices: ["default"], audio_formats: [:pcm], word_timing: false}
    end
  end

  defmodule ErrorBatchProvider do
    use Livekit.Agents.TTS

    @impl true
    def synthesize(_text, _opts), do: {:error, :synthesis_failed}

    @impl true
    def capabilities do
      %{streaming: false, voices: ["default"], audio_formats: [:pcm], word_timing: false}
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
      assert is_list(caps.voices)
      assert is_list(caps.audio_formats)
      assert is_boolean(caps.word_timing)
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
  # synthesize/2
  # ---------------------------------------------------------------------------

  describe "synthesize/2" do
    test "delegates to underlying batch provider" do
      audio_data = <<1, 2, 3, 4>>
      config = %Config{provider: {BatchProvider, %{audio: audio_data}}}
      assert {:ok, audio} = StreamAdapter.synthesize("Hello", config: config)
      assert audio == audio_data
    end

    test "propagates errors from underlying provider" do
      config = %Config{provider: {ErrorBatchProvider, %{}}}
      assert {:error, :synthesis_failed} = StreamAdapter.synthesize("Hello", config: config)
    end
  end

  # ---------------------------------------------------------------------------
  # stream/1 — basic protocol
  # ---------------------------------------------------------------------------

  describe "stream/1" do
    test "returns {:ok, pid}" do
      config = %Config{provider: {BatchProvider, %{}}}
      assert {:ok, pid} = StreamAdapter.stream(config)
      assert is_pid(pid)
      send(pid, :flush)
    end

    test "emits :stream_done on flush with no text" do
      config = %Config{provider: {BatchProvider, %{}}}
      {:ok, stream_pid} = StreamAdapter.stream(config)
      send(stream_pid, :flush)

      assert_receive :stream_done, 1000
    end

    test "synthesizes text chunk and emits AudioFrame on flush" do
      config = %Config{provider: {BatchProvider, %{}}}
      {:ok, stream_pid} = StreamAdapter.stream(config)

      send(stream_pid, {:text_chunk, "Hello there"})
      send(stream_pid, :flush)

      assert_receive {:audio_frame, %AudioFrame{}}, 1000
      assert_receive :stream_done, 1000
    end

    test "emitted AudioFrame has correct sample_rate from config" do
      config = %Config{provider: {BatchProvider, %{}}, sample_rate: 24_000}
      {:ok, stream_pid} = StreamAdapter.stream(config)

      send(stream_pid, {:text_chunk, "Test audio"})
      send(stream_pid, :flush)

      assert_receive {:audio_frame, %AudioFrame{sample_rate: 24_000}}, 1000
      assert_receive :stream_done, 1000
    end

    test "synthesizes at sentence boundaries when sentence_tokenize: true" do
      config = %Config{provider: {BatchProvider, %{}}, sentence_tokenize: true}
      {:ok, stream_pid} = StreamAdapter.stream(config)

      send(stream_pid, {:text_chunk, "Hello! How are you?"})
      send(stream_pid, :flush)

      # Expect two audio frames (one per sentence) plus stream_done
      assert_receive {:audio_frame, %AudioFrame{}}, 1000
      assert_receive {:audio_frame, %AudioFrame{}}, 1000
      assert_receive :stream_done, 1000
    end

    test "does not split sentences when sentence_tokenize: false" do
      config = %Config{provider: {BatchProvider, %{}}, sentence_tokenize: false}
      {:ok, stream_pid} = StreamAdapter.stream(config)

      send(stream_pid, {:text_chunk, "Hello! How are you?"})
      send(stream_pid, :flush)

      # Expect exactly one frame (no sentence splitting)
      assert_receive {:audio_frame, %AudioFrame{}}, 1000
      assert_receive :stream_done, 1000
      refute_receive {:audio_frame, %AudioFrame{}}, 100
    end

    test "accumulates multiple text chunks before flush" do
      config = %Config{provider: {BatchProvider, %{}}, sentence_tokenize: false}
      {:ok, stream_pid} = StreamAdapter.stream(config)

      send(stream_pid, {:text_chunk, "Part one. "})
      send(stream_pid, {:text_chunk, "Part two."})
      send(stream_pid, :flush)

      assert_receive {:audio_frame, %AudioFrame{}}, 1000
      assert_receive :stream_done, 1000
    end

    test "sends {:error, reason} and continues when provider fails" do
      config = %Config{provider: {ErrorBatchProvider, %{}}, sentence_tokenize: false}
      {:ok, stream_pid} = StreamAdapter.stream(config)

      send(stream_pid, {:text_chunk, "This will fail"})
      send(stream_pid, :flush)

      assert_receive {:error, :synthesis_failed}, 1000
      assert_receive :stream_done, 1000
    end
  end
end

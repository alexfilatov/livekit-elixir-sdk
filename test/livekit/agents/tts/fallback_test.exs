defmodule Livekit.Agents.TTS.FallbackTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.TTS.Fallback
  alias Livekit.Agents.TTS.Fallback.Config
  alias Livekit.Agents.AudioFrame

  # ---------------------------------------------------------------------------
  # Minimal mock TTS providers
  # ---------------------------------------------------------------------------

  defmodule OkProvider do
    use Livekit.Agents.TTS

    @impl true
    def synthesize(_text, opts) do
      config = Keyword.get(opts, :config, %{})
      audio = Map.get(config, :audio, <<1, 2, 3, 4>>)
      {:ok, audio}
    end

    @impl true
    def capabilities do
      %{streaming: false, voices: ["default"], audio_formats: [:pcm], word_timing: false}
    end
  end

  defmodule ErrorProvider do
    use Livekit.Agents.TTS

    @impl true
    def synthesize(_text, _opts), do: {:error, :api_down}

    @impl true
    def capabilities do
      %{streaming: false, voices: ["default"], audio_formats: [:pcm], word_timing: false}
    end
  end

  defmodule StreamingProvider do
    use Livekit.Agents.TTS

    @impl true
    def synthesize(_text, _opts), do: {:ok, <<5, 6, 7, 8>>}

    @impl true
    def stream(_config) do
      subscriber = self()

      pid =
        spawn(fn ->
          frame = %Livekit.Agents.AudioFrame{data: <<5, 6, 7, 8>>, sample_rate: 48_000}
          send(subscriber, {:audio_frame, frame})
          send(subscriber, :stream_done)
        end)

      {:ok, pid}
    end

    @impl true
    def capabilities do
      %{streaming: true, voices: ["stream_voice"], audio_formats: [:pcm], word_timing: false}
    end
  end

  defmodule FailingStreamProvider do
    use Livekit.Agents.TTS

    @impl true
    def synthesize(_text, _opts), do: {:ok, <<0>>}

    @impl true
    def stream(_config), do: {:error, :stream_unavailable}

    @impl true
    def capabilities do
      %{streaming: true, voices: ["default"], audio_formats: [:pcm], word_timing: false}
    end
  end

  # ---------------------------------------------------------------------------
  # capabilities/0
  # ---------------------------------------------------------------------------

  describe "capabilities/0" do
    test "returns a valid capability map" do
      caps = Fallback.capabilities()
      assert is_boolean(caps.streaming)
      assert is_list(caps.voices)
      assert is_list(caps.audio_formats)
      assert is_boolean(caps.word_timing)
    end
  end

  # ---------------------------------------------------------------------------
  # validate_config/1
  # ---------------------------------------------------------------------------

  describe "validate_config/1" do
    test "returns error when primary is nil" do
      config = %Config{primary: nil, secondary: {OkProvider, %{}}}
      assert {:error, :missing_primary} = Fallback.validate_config(config)
    end

    test "returns error when secondary is nil" do
      config = %Config{primary: {OkProvider, %{}}, secondary: nil}
      assert {:error, :missing_secondary} = Fallback.validate_config(config)
    end

    test "returns :ok with valid primary and secondary" do
      config = %Config{primary: {OkProvider, %{}}, secondary: {OkProvider, %{}}}
      assert :ok = Fallback.validate_config(config)
    end
  end

  # ---------------------------------------------------------------------------
  # synthesize/2 — primary succeeds
  # ---------------------------------------------------------------------------

  describe "synthesize/2 when primary succeeds" do
    test "returns primary audio without calling secondary" do
      config = %Config{
        primary: {OkProvider, %{audio: <<1, 2, 3, 4>>}},
        secondary: {OkProvider, %{audio: <<9, 9, 9, 9>>}}
      }

      assert {:ok, audio} = Fallback.synthesize("Hello", config: config)
      assert audio == <<1, 2, 3, 4>>
    end

    test "returns binary audio" do
      config = %Config{
        primary: {OkProvider, %{}},
        secondary: {ErrorProvider, %{}}
      }

      assert {:ok, audio} = Fallback.synthesize("test", config: config)
      assert is_binary(audio)
    end
  end

  # ---------------------------------------------------------------------------
  # synthesize/2 — primary fails, secondary used
  # ---------------------------------------------------------------------------

  describe "synthesize/2 when primary fails" do
    test "falls back to secondary on primary error" do
      config = %Config{
        primary: {ErrorProvider, %{}},
        secondary: {OkProvider, %{audio: <<9, 8, 7>>}}
      }

      assert {:ok, audio} = Fallback.synthesize("Hello", config: config)
      assert audio == <<9, 8, 7>>
    end

    test "returns error when both primary and secondary fail" do
      config = %Config{
        primary: {ErrorProvider, %{}},
        secondary: {ErrorProvider, %{}}
      }

      assert {:error, :api_down} = Fallback.synthesize("Hello", config: config)
    end
  end

  # ---------------------------------------------------------------------------
  # stream/1 — primary stream succeeds
  # ---------------------------------------------------------------------------

  describe "stream/1 when primary supports streaming" do
    test "delegates stream to primary provider" do
      config = %Config{
        primary: {StreamingProvider, %{}},
        secondary: {OkProvider, %{}}
      }

      assert {:ok, _pid} = Fallback.stream(config)

      assert_receive {:audio_frame, %AudioFrame{}}, 500
      assert_receive :stream_done, 500
    end
  end

  # ---------------------------------------------------------------------------
  # stream/1 — primary stream fails, secondary used
  # ---------------------------------------------------------------------------

  describe "stream/1 when primary stream fails" do
    test "falls back to secondary stream when primary stream errors" do
      config = %Config{
        primary: {FailingStreamProvider, %{}},
        secondary: {StreamingProvider, %{}}
      }

      assert {:ok, _pid} = Fallback.stream(config)

      assert_receive {:audio_frame, %AudioFrame{}}, 500
      assert_receive :stream_done, 500
    end

    test "returns error when secondary also lacks streaming" do
      config = %Config{
        primary: {ErrorProvider, %{}},
        secondary: {ErrorProvider, %{}}
      }

      assert {:error, :no_provider_supports_streaming} = Fallback.stream(config)
    end

    test "returns error when primary fails streaming and secondary has no stream/1" do
      config = %Config{
        primary: {FailingStreamProvider, %{}},
        secondary: {OkProvider, %{}}
      }

      assert {:error, :secondary_does_not_support_streaming} = Fallback.stream(config)
    end
  end
end

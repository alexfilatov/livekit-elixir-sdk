defmodule Livekit.Agents.STT.FallbackTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.STT.Fallback
  alias Livekit.Agents.STT.Fallback.Config
  alias Livekit.Agents.STT.SpeechEvent

  # ---------------------------------------------------------------------------
  # Minimal mock STT providers
  # ---------------------------------------------------------------------------

  defmodule OkProvider do
    use Livekit.Agents.STT

    @impl true
    def transcribe(_audio, opts) do
      config = Keyword.get(opts, :config, %{})
      text = Map.get(config, :text, "ok transcript")
      {:ok, %SpeechEvent{type: :final, text: text, confidence: 0.99, language: "en"}}
    end

    @impl true
    def capabilities do
      %{streaming: false, interim_results: false, diarization: false, languages: ["en"]}
    end
  end

  defmodule ErrorProvider do
    use Livekit.Agents.STT

    @impl true
    def transcribe(_audio, _opts), do: {:error, :api_down}

    @impl true
    def capabilities do
      %{streaming: false, interim_results: false, diarization: false, languages: ["en"]}
    end
  end

  defmodule StreamingProvider do
    use Livekit.Agents.STT

    @impl true
    def transcribe(_audio, _opts) do
      {:ok, %SpeechEvent{type: :final, text: "streamed", confidence: 0.95, language: "en"}}
    end

    @impl true
    def stream(_config) do
      subscriber = self()

      pid =
        spawn(fn ->
          send(subscriber, {:speech_event, %SpeechEvent{type: :start}})
          send(subscriber, {:speech_event, %SpeechEvent{type: :final, text: "streamed"}})
          send(subscriber, {:speech_event, %SpeechEvent{type: :end}})
        end)

      {:ok, pid}
    end

    @impl true
    def capabilities do
      %{streaming: true, interim_results: false, diarization: false, languages: ["en"]}
    end
  end

  defmodule FailingStreamProvider do
    use Livekit.Agents.STT

    @impl true
    def transcribe(_audio, _opts), do: {:ok, %SpeechEvent{type: :final, text: "batch"}}

    @impl true
    def stream(_config), do: {:error, :stream_unavailable}

    @impl true
    def capabilities do
      %{streaming: true, interim_results: false, diarization: false, languages: ["en"]}
    end
  end

  # ---------------------------------------------------------------------------
  # capabilities/0
  # ---------------------------------------------------------------------------

  describe "capabilities/0" do
    test "returns a valid capability map" do
      caps = Fallback.capabilities()
      assert is_boolean(caps.streaming)
      assert is_boolean(caps.interim_results)
      assert is_boolean(caps.diarization)
      assert is_list(caps.languages)
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
  # transcribe/2 — primary succeeds
  # ---------------------------------------------------------------------------

  describe "transcribe/2 when primary succeeds" do
    setup do
      config = %Config{
        primary: {OkProvider, %{text: "from primary"}},
        secondary: {OkProvider, %{text: "from secondary"}}
      }

      {:ok, config: config}
    end

    test "returns primary result without calling secondary", %{config: config} do
      audio = :binary.copy(<<0>>, 1000)
      assert {:ok, event} = Fallback.transcribe(audio, config: config)
      assert event.text == "from primary"
    end

    test "returns SpeechEvent with :final type", %{config: config} do
      {:ok, event} = Fallback.transcribe(<<0>>, config: config)
      assert event.type == :final
    end
  end

  # ---------------------------------------------------------------------------
  # transcribe/2 — primary fails, secondary used
  # ---------------------------------------------------------------------------

  describe "transcribe/2 when primary fails" do
    setup do
      config = %Config{
        primary: {ErrorProvider, %{}},
        secondary: {OkProvider, %{text: "secondary fallback"}}
      }

      {:ok, config: config}
    end

    test "falls back to secondary on primary error", %{config: config} do
      audio = :binary.copy(<<0>>, 1000)
      assert {:ok, event} = Fallback.transcribe(audio, config: config)
      assert event.text == "secondary fallback"
    end

    test "returns error when both primary and secondary fail" do
      config = %Config{
        primary: {ErrorProvider, %{}},
        secondary: {ErrorProvider, %{}}
      }

      assert {:error, :api_down} = Fallback.transcribe(<<>>, config: config)
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

      assert_receive {:speech_event, %SpeechEvent{type: :start}}, 500
      assert_receive {:speech_event, %SpeechEvent{type: :final}}, 500
      assert_receive {:speech_event, %SpeechEvent{type: :end}}, 500
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

      assert_receive {:speech_event, %SpeechEvent{type: :start}}, 500
      assert_receive {:speech_event, %SpeechEvent{type: :final}}, 500
      assert_receive {:speech_event, %SpeechEvent{type: :end}}, 500
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

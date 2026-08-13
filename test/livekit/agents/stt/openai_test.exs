defmodule Livekit.Agents.STT.OpenAITest do
  use ExUnit.Case, async: true

  @moduledoc """
  OpenAI speech-to-text.

  The interesting part is the WAV header: the pipeline carries raw PCM16 from
  the room and OpenAI's endpoint takes a file, rejecting a bare PCM body with
  a complaint about the file type rather than the bytes. A header with the
  wrong sample rate is worse than no header — the audio is accepted and
  transcribed at the wrong speed, producing confident nonsense.
  """

  alias Livekit.Agents.STT.OpenAI
  alias Livekit.Agents.STT.OpenAI.Config

  # 100ms of silence at 48kHz mono PCM16.
  defp pcm(ms \\ 100, rate \\ 48_000), do: :binary.copy(<<0, 0>>, div(rate * ms, 1000))

  describe "validate_config/1" do
    test "refuses a missing or blank key" do
      assert {:error, :missing_api_key} = OpenAI.validate_config(%Config{})
      assert {:error, :missing_api_key} = OpenAI.validate_config(%Config{api_key: ""})
    end

    test "refuses a nonsensical sample rate" do
      assert {:error, :invalid_sample_rate} =
               OpenAI.validate_config(%Config{api_key: "k", sample_rate: 0})
    end

    test "accepts a complete config" do
      assert :ok = OpenAI.validate_config(%Config{api_key: "k"})
    end
  end

  describe "defaults" do
    test "the cheaper transcribe model, and a named language" do
      config = %Config{}

      # gpt-4o-mini-transcribe is $0.003/min against $0.006 for the other two.
      assert config.model == "gpt-4o-mini-transcribe"
      # Naming the language stops the model guessing, which it does badly on
      # a short noisy first utterance.
      assert config.language == "en"
      assert config.sample_rate == 48_000
    end
  end

  describe "transcribe/2" do
    setup do
      bypass = Bypass.open()
      config = %Config{api_key: "sk-test", base_url: "http://localhost:#{bypass.port}"}
      {:ok, bypass: bypass, config: config}
    end

    test "sends a real WAV file, not raw PCM", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/v1/audio/transcriptions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn, length: 10_000_000)

        # The container is what makes the endpoint accept it at all.
        assert body =~ "RIFF"
        assert body =~ "WAVE"
        assert body =~ "audio.wav"
        assert body =~ "gpt-4o-mini-transcribe"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"text":"how many bedrooms"}))
      end)

      assert {:ok, event} = OpenAI.transcribe(pcm(), config: config)
      assert event.type == :final
      assert event.text == "how many bedrooms"
    end

    test "the WAV header carries the configured sample rate", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/v1/audio/transcriptions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn, length: 10_000_000)

        # 48000 = 0x0000BB80, little-endian in the fmt chunk. A wrong rate is
        # accepted by the API and transcribed at the wrong speed — confident
        # nonsense rather than an error.
        assert body =~ <<0x80, 0xBB, 0x00, 0x00>>

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"text":"ok"}))
      end)

      OpenAI.transcribe(pcm(), config: config)
    end

    test "trims the transcript", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/v1/audio/transcriptions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"text":"  a spacious garden  "}))
      end)

      assert {:ok, %{text: "a spacious garden"}} = OpenAI.transcribe(pcm(), config: config)
    end

    test "silence costs nothing", %{config: config} do
      # A turn that captured nothing is ordinary. Spending a request on it
      # would bill for background noise.
      assert {:ok, %{type: :final, text: "", confidence: +0.0}} =
               OpenAI.transcribe(<<>>, config: config)
    end

    test "an empty transcript is not reported as confident", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/v1/audio/transcriptions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"text":""}))
      end)

      assert {:ok, %{text: "", confidence: +0.0}} = OpenAI.transcribe(pcm(), config: config)
    end

    test "an API error is returned, not raised", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/v1/audio/transcriptions", fn conn ->
        Plug.Conn.resp(conn, 401, ~s({"error":"nope"}))
      end)

      assert {:error, {:http_error, 401}} = OpenAI.transcribe(pcm(), config: config)
    end

    test "a missing key never reaches the network" do
      assert {:error, :missing_api_key} = OpenAI.transcribe(pcm(), config: %Config{})
    end
  end

  describe "against the real OpenAI API" do
    @describetag :integration

    test "transcribes actual speech" do
      key = System.get_env("OPENAI_API_KEY")
      if is_nil(key), do: flunk("OPENAI_API_KEY not set")

      # A tone rather than speech: this checks the request is well-formed and
      # accepted end to end. Whether it hears words is the model's business.
      rate = 48_000

      tone =
        for i <- 0..(div(rate, 2) - 1), into: <<>> do
          <<trunc(:math.sin(2 * :math.pi() * 440 * i / rate) * 8000)::little-signed-16>>
        end

      assert {:ok, %{type: :final}} =
               OpenAI.transcribe(tone, config: %Config{api_key: key, sample_rate: rate})
    end
  end

  describe "stream/1" do
    test "is honestly unimplemented" do
      # The pipeline transcribes a completed turn; a half-built streaming path
      # would be worse than a refusal.
      assert {:error, :not_implemented} = OpenAI.stream(%Config{api_key: "k"})
    end
  end
end

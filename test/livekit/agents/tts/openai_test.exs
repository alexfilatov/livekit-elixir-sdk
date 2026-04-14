defmodule Livekit.Agents.TTS.OpenAITest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.TTS.OpenAI
  alias Livekit.Agents.TTS.OpenAI.{Cache, Config}

  # ── capabilities ──────────────────────────────────────────────────────────

  describe "capabilities/0" do
    test "returns correct capability map" do
      caps = OpenAI.capabilities()
      assert caps.streaming == false
      assert caps.word_timing == false
      assert "alloy" in caps.voices
      assert "echo" in caps.voices
      assert "fable" in caps.voices
      assert "onyx" in caps.voices
      assert "nova" in caps.voices
      assert "shimmer" in caps.voices
      assert :pcm in caps.audio_formats
      assert :mp3 in caps.audio_formats
      assert :opus in caps.audio_formats
      assert :aac in caps.audio_formats
      assert :flac in caps.audio_formats
    end

    test "returns exactly 6 voices" do
      assert length(OpenAI.capabilities().voices) == 6
    end

    test "returns exactly 5 audio formats" do
      assert length(OpenAI.capabilities().audio_formats) == 5
    end
  end

  # ── validate_config ────────────────────────────────────────────────────────

  describe "validate_config/1" do
    test "mock: true passes without api_key" do
      assert :ok = OpenAI.validate_config(%Config{mock: true})
    end

    test "missing api_key in real mode returns error" do
      assert {:error, :missing_api_key} =
               OpenAI.validate_config(%Config{mock: false, api_key: nil})
    end

    test "empty api_key in real mode returns error" do
      assert {:error, :missing_api_key} =
               OpenAI.validate_config(%Config{mock: false, api_key: ""})
    end

    test "invalid speed (too low) returns error" do
      assert {:error, :invalid_speed} = OpenAI.validate_config(%Config{api_key: "k", speed: 0.1})
    end

    test "invalid speed (too high) returns error" do
      assert {:error, :invalid_speed} = OpenAI.validate_config(%Config{api_key: "k", speed: 5.0})
    end

    test "valid config returns :ok" do
      assert :ok = OpenAI.validate_config(%Config{api_key: "valid-key"})
    end

    test "boundary speed 0.25 is valid" do
      assert :ok = OpenAI.validate_config(%Config{api_key: "k", speed: 0.25})
    end

    test "boundary speed 4.0 is valid" do
      assert :ok = OpenAI.validate_config(%Config{api_key: "k", speed: 4.0})
    end
  end

  # ── mock mode ─────────────────────────────────────────────────────────────

  describe "synthesize/2 mock mode" do
    test "returns audio binary for mock: true" do
      config = %Config{mock: true}
      assert {:ok, audio} = OpenAI.synthesize("Hello, world!", config: config)
      assert is_binary(audio)
      assert byte_size(audio) > 0
    end

    test "different voices produce different audio" do
      alloy_config = %Config{mock: true, voice: :alloy}
      shimmer_config = %Config{mock: true, voice: :shimmer}
      {:ok, alloy_audio} = OpenAI.synthesize("Hello", config: alloy_config)
      {:ok, shimmer_audio} = OpenAI.synthesize("Hello", config: shimmer_config)
      # Different frequencies => different waveforms
      assert alloy_audio != shimmer_audio
    end

    test "all voices produce non-empty audio" do
      voices = [:alloy, :echo, :fable, :onyx, :nova, :shimmer]

      for voice <- voices do
        config = %Config{mock: true, voice: voice}
        assert {:ok, audio} = OpenAI.synthesize("Test audio", config: config)
        assert byte_size(audio) > 0, "Expected non-empty audio for voice #{voice}"
      end
    end

    test "nil api_key with mock: false falls back to mock mode" do
      config = %Config{api_key: nil, mock: false}
      assert {:ok, audio} = OpenAI.synthesize("Test", config: config)
      assert byte_size(audio) > 0
    end

    test "empty api_key with mock: false falls back to mock mode" do
      config = %Config{api_key: "", mock: false}
      assert {:ok, audio} = OpenAI.synthesize("Test", config: config)
      assert byte_size(audio) > 0
    end

    test "longer text produces more audio samples" do
      config = %Config{mock: true}
      {:ok, short_audio} = OpenAI.synthesize("Hi", config: config)
      {:ok, long_audio} = OpenAI.synthesize(String.duplicate("Hello world ", 20), config: config)
      assert byte_size(long_audio) > byte_size(short_audio)
    end
  end

  # ── real HTTP via Bypass ───────────────────────────────────────────────────

  describe "synthesize/2 real HTTP" do
    setup do
      bypass = Bypass.open()
      config = %Config{api_key: "test-key", base_url: "http://localhost:#{bypass.port}"}
      {:ok, bypass: bypass, config: config}
    end

    test "sends correct JSON body to /v1/audio/speech", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/v1/audio/speech", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)
        assert request["model"] == "tts-1"
        assert request["input"] == "Hello Bypass"
        assert request["voice"] == "alloy"
        assert request["response_format"] == "pcm"
        assert request["speed"] == 1.0

        conn
        |> Plug.Conn.put_resp_content_type("audio/pcm")
        |> Plug.Conn.send_resp(200, <<1, 2, 3, 4>>)
      end)

      assert {:ok, audio} = OpenAI.synthesize("Hello Bypass", config: config)
      assert audio == <<1, 2, 3, 4>>
    end

    test "voice and format overrides are sent in request", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/v1/audio/speech", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)
        assert request["voice"] == "nova"
        assert request["response_format"] == "mp3"

        conn
        |> Plug.Conn.put_resp_content_type("audio/mpeg")
        |> Plug.Conn.send_resp(200, <<5, 6, 7, 8>>)
      end)

      assert {:ok, audio} = OpenAI.synthesize("Hi", config: config, voice: :nova, format: :mp3)
      assert audio == <<5, 6, 7, 8>>
    end

    test "returns raw audio bytes from server (not JSON-decoded)", %{
      bypass: bypass,
      config: config
    } do
      raw_audio = :crypto.strong_rand_bytes(256)

      Bypass.expect_once(bypass, "POST", "/v1/audio/speech", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("audio/pcm")
        |> Plug.Conn.send_resp(200, raw_audio)
      end)

      assert {:ok, received} = OpenAI.synthesize("Audio test", config: config)
      assert received == raw_audio
    end

    test "returns {:error, {:api_error, 429, _}} on rate limit", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/v1/audio/speech", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(429, Jason.encode!(%{"error" => "rate limited"}))
      end)

      assert {:error, {:api_error, 429, _}} = OpenAI.synthesize("Test", config: config)
    end

    test "returns {:error, {:api_error, 401, _}} on unauthorized", %{
      bypass: bypass,
      config: config
    } do
      Bypass.expect_once(bypass, "POST", "/v1/audio/speech", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(401, Jason.encode!(%{"error" => "invalid_api_key"}))
      end)

      assert {:error, {:api_error, 401, _}} = OpenAI.synthesize("Test", config: config)
    end

    test "returns {:error, _} on network failure", %{bypass: bypass, config: config} do
      Bypass.down(bypass)
      assert {:error, _reason} = OpenAI.synthesize("Test", config: config)
    end

    test "cache hit avoids second HTTP request", %{bypass: bypass, config: config} do
      {:ok, cache_pid} = Cache.start_link()

      # Bypass expects exactly ONE call; second call must come from cache
      Bypass.expect_once(bypass, "POST", "/v1/audio/speech", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("audio/pcm")
        |> Plug.Conn.send_resp(200, <<10, 20, 30>>)
      end)

      assert {:ok, audio1} = OpenAI.synthesize("Cached text", config: config, cache: cache_pid)
      assert {:ok, audio2} = OpenAI.synthesize("Cached text", config: config, cache: cache_pid)
      assert audio1 == audio2
      assert audio1 == <<10, 20, 30>>
      # If Bypass were called twice it would raise — test passing proves cache hit on 2nd call
    end

    test "different texts produce separate cache entries", %{bypass: bypass, config: config} do
      {:ok, cache_pid} = Cache.start_link()

      Bypass.expect(bypass, "POST", "/v1/audio/speech", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        audio =
          case request["input"] do
            "Text A" -> <<1, 2>>
            "Text B" -> <<3, 4>>
            _ -> <<0>>
          end

        conn
        |> Plug.Conn.put_resp_content_type("audio/pcm")
        |> Plug.Conn.send_resp(200, audio)
      end)

      assert {:ok, <<1, 2>>} = OpenAI.synthesize("Text A", config: config, cache: cache_pid)
      assert {:ok, <<3, 4>>} = OpenAI.synthesize("Text B", config: config, cache: cache_pid)
    end

    test "tts-1-hd model name is serialized correctly", %{bypass: bypass, config: config} do
      hd_config = %{config | model: :tts_1_hd}

      Bypass.expect_once(bypass, "POST", "/v1/audio/speech", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)
        assert request["model"] == "tts-1-hd"

        conn
        |> Plug.Conn.put_resp_content_type("audio/pcm")
        |> Plug.Conn.send_resp(200, <<0>>)
      end)

      assert {:ok, _} = OpenAI.synthesize("HD test", config: hd_config)
    end
  end
end

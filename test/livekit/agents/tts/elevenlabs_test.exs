defmodule Livekit.Agents.TTS.ElevenLabsTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.TTS.ElevenLabs
  alias Livekit.Agents.TTS.ElevenLabs.Config
  alias Livekit.Agents.TTS.OpenAI.Cache

  # ── capabilities ──────────────────────────────────────────────────────────

  describe "capabilities/0" do
    test "returns correct capability map shape" do
      caps = ElevenLabs.capabilities()
      assert caps.streaming == false
      assert caps.word_timing == false
      assert is_list(caps.voices)
      assert is_list(caps.audio_formats)
    end

    test "rachel voice is listed" do
      caps = ElevenLabs.capabilities()
      assert "21m00Tcm4TlvDq8ikWAM" in caps.voices
    end

    test "pcm format is supported" do
      assert :pcm in ElevenLabs.capabilities().audio_formats
    end

    test "voices list is non-empty" do
      assert length(ElevenLabs.capabilities().voices) > 0
    end
  end

  # ── validate_config ────────────────────────────────────────────────────────

  describe "validate_config/1" do
    test "mock: true passes without api_key" do
      assert :ok = ElevenLabs.validate_config(%Config{mock: true})
    end

    test "missing api_key in real mode returns error" do
      assert {:error, :missing_api_key} =
               ElevenLabs.validate_config(%Config{mock: false, api_key: nil})
    end

    test "empty api_key in real mode returns error" do
      assert {:error, :missing_api_key} =
               ElevenLabs.validate_config(%Config{mock: false, api_key: ""})
    end

    test "missing voice_id returns error" do
      assert {:error, :missing_voice_id} =
               ElevenLabs.validate_config(%Config{api_key: "k", voice_id: ""})
    end

    test "nil voice_id returns error" do
      assert {:error, :missing_voice_id} =
               ElevenLabs.validate_config(%Config{api_key: "k", voice_id: nil})
    end

    test "missing model_id returns error" do
      assert {:error, :missing_model_id} =
               ElevenLabs.validate_config(%Config{api_key: "k", model_id: ""})
    end

    test "nil model_id returns error" do
      assert {:error, :missing_model_id} =
               ElevenLabs.validate_config(%Config{api_key: "k", model_id: nil})
    end

    test "stability below 0.0 returns error" do
      assert {:error, :invalid_stability} =
               ElevenLabs.validate_config(%Config{api_key: "k", stability: -0.1})
    end

    test "stability above 1.0 returns error" do
      assert {:error, :invalid_stability} =
               ElevenLabs.validate_config(%Config{api_key: "k", stability: 1.1})
    end

    test "boundary stability 0.0 is valid" do
      assert :ok = ElevenLabs.validate_config(%Config{api_key: "k", stability: 0.0})
    end

    test "boundary stability 1.0 is valid" do
      assert :ok = ElevenLabs.validate_config(%Config{api_key: "k", stability: 1.0})
    end

    test "similarity_boost below 0.0 returns error" do
      assert {:error, :invalid_similarity_boost} =
               ElevenLabs.validate_config(%Config{api_key: "k", similarity_boost: -0.1})
    end

    test "similarity_boost above 1.0 returns error" do
      assert {:error, :invalid_similarity_boost} =
               ElevenLabs.validate_config(%Config{api_key: "k", similarity_boost: 1.1})
    end

    test "boundary similarity_boost 0.0 is valid" do
      assert :ok = ElevenLabs.validate_config(%Config{api_key: "k", similarity_boost: 0.0})
    end

    test "boundary similarity_boost 1.0 is valid" do
      assert :ok = ElevenLabs.validate_config(%Config{api_key: "k", similarity_boost: 1.0})
    end

    test "valid config with all defaults returns :ok" do
      assert :ok = ElevenLabs.validate_config(%Config{api_key: "valid-key"})
    end

    test "valid config with all voice settings returns :ok" do
      assert :ok =
               ElevenLabs.validate_config(%Config{
                 api_key: "k",
                 stability: 0.5,
                 similarity_boost: 0.75
               })
    end
  end

  # ── mock mode ─────────────────────────────────────────────────────────────

  describe "synthesize/2 mock mode" do
    test "returns audio binary for mock: true" do
      config = %Config{mock: true}
      assert {:ok, audio} = ElevenLabs.synthesize("Hello, world!", config: config)
      assert is_binary(audio)
      assert byte_size(audio) > 0
    end

    test "different voice IDs produce different audio" do
      rachel_config = %Config{mock: true, voice_id: "21m00Tcm4TlvDq8ikWAM"}
      other_config = %Config{mock: true, voice_id: "EXAVITQu4vr4xnSDxMaL"}
      {:ok, rachel_audio} = ElevenLabs.synthesize("Hello", config: rachel_config)
      {:ok, other_audio} = ElevenLabs.synthesize("Hello", config: other_config)
      assert rachel_audio != other_audio
    end

    test "nil api_key with mock: false falls back to mock mode" do
      config = %Config{api_key: nil, mock: false}
      assert {:ok, audio} = ElevenLabs.synthesize("Test", config: config)
      assert byte_size(audio) > 0
    end

    test "empty api_key with mock: false falls back to mock mode" do
      config = %Config{api_key: "", mock: false}
      assert {:ok, audio} = ElevenLabs.synthesize("Test", config: config)
      assert byte_size(audio) > 0
    end

    test "longer text produces more audio samples" do
      config = %Config{mock: true}
      {:ok, short_audio} = ElevenLabs.synthesize("Hi", config: config)

      {:ok, long_audio} =
        ElevenLabs.synthesize(String.duplicate("Hello world ", 20), config: config)

      assert byte_size(long_audio) > byte_size(short_audio)
    end

    test "voice_id override option is honoured in mock mode" do
      config = %Config{mock: true, voice_id: "21m00Tcm4TlvDq8ikWAM"}

      {:ok, rachel_audio} = ElevenLabs.synthesize("Hello", config: config)

      {:ok, override_audio} =
        ElevenLabs.synthesize("Hello",
          config: config,
          voice_id: "EXAVITQu4vr4xnSDxMaL"
        )

      assert rachel_audio != override_audio
    end

    test "known voice IDs each produce non-empty audio" do
      voice_ids = [
        "21m00Tcm4TlvDq8ikWAM",
        "AZnzlk1XvdvUeBnXmlld",
        "EXAVITQu4vr4xnSDxMaL",
        "ErXwobaYiN019PkySvjV",
        "MF3mGyEYCl7XYWbV9V6O"
      ]

      for voice_id <- voice_ids do
        config = %Config{mock: true, voice_id: voice_id}
        assert {:ok, audio} = ElevenLabs.synthesize("Test audio", config: config)
        assert byte_size(audio) > 0, "Expected non-empty audio for voice_id #{voice_id}"
      end
    end
  end

  # ── real HTTP via Bypass ───────────────────────────────────────────────────

  describe "synthesize/2 real HTTP" do
    setup do
      bypass = Bypass.open()

      config = %Config{
        api_key: "test-xi-key",
        base_url: "http://localhost:#{bypass.port}"
      }

      {:ok, bypass: bypass, config: config}
    end

    test "sends POST to correct path and returns audio", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "POST",
        "/v1/text-to-speech/#{config.voice_id}",
        fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          request = Jason.decode!(body)
          assert request["text"] == "Hello ElevenLabs"
          assert request["model_id"] == "eleven_turbo_v2_5"

          conn
          |> Plug.Conn.put_resp_content_type("audio/mpeg")
          |> Plug.Conn.send_resp(200, <<1, 2, 3, 4>>)
        end
      )

      assert {:ok, audio} = ElevenLabs.synthesize("Hello ElevenLabs", config: config)
      assert audio == <<1, 2, 3, 4>>
    end

    test "sends xi-api-key header", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "POST",
        "/v1/text-to-speech/#{config.voice_id}",
        fn conn ->
          headers = Map.new(conn.req_headers)
          assert Map.get(headers, "xi-api-key") == "test-xi-key"

          conn
          |> Plug.Conn.put_resp_content_type("audio/mpeg")
          |> Plug.Conn.send_resp(200, <<10, 20>>)
        end
      )

      assert {:ok, _audio} = ElevenLabs.synthesize("Auth test", config: config)
    end

    test "voice_id override changes request path", %{bypass: bypass, config: config} do
      custom_voice = "AZnzlk1XvdvUeBnXmlld"

      Bypass.expect_once(bypass, "POST", "/v1/text-to-speech/#{custom_voice}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("audio/mpeg")
        |> Plug.Conn.send_resp(200, <<5, 6, 7, 8>>)
      end)

      assert {:ok, audio} =
               ElevenLabs.synthesize("Voice override", config: config, voice_id: custom_voice)

      assert audio == <<5, 6, 7, 8>>
    end

    test "sends voice_settings when stability is set", %{bypass: bypass, config: config} do
      config_with_settings = %{config | stability: 0.5, similarity_boost: 0.75}

      Bypass.expect_once(
        bypass,
        "POST",
        "/v1/text-to-speech/#{config.voice_id}",
        fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          request = Jason.decode!(body)
          voice_settings = request["voice_settings"]
          assert is_map(voice_settings)
          assert voice_settings["stability"] == 0.5
          assert voice_settings["similarity_boost"] == 0.75

          conn
          |> Plug.Conn.put_resp_content_type("audio/mpeg")
          |> Plug.Conn.send_resp(200, <<0>>)
        end
      )

      assert {:ok, _} = ElevenLabs.synthesize("Settings test", config: config_with_settings)
    end

    test "omits voice_settings when stability and similarity_boost are nil", %{
      bypass: bypass,
      config: config
    } do
      config_no_settings = %{config | stability: nil, similarity_boost: nil}

      Bypass.expect_once(
        bypass,
        "POST",
        "/v1/text-to-speech/#{config.voice_id}",
        fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          request = Jason.decode!(body)
          refute Map.has_key?(request, "voice_settings")

          conn
          |> Plug.Conn.put_resp_content_type("audio/mpeg")
          |> Plug.Conn.send_resp(200, <<0>>)
        end
      )

      assert {:ok, _} = ElevenLabs.synthesize("No settings", config: config_no_settings)
    end

    test "returns raw audio bytes from server", %{bypass: bypass, config: config} do
      raw_audio = :crypto.strong_rand_bytes(256)

      Bypass.expect_once(
        bypass,
        "POST",
        "/v1/text-to-speech/#{config.voice_id}",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("audio/mpeg")
          |> Plug.Conn.send_resp(200, raw_audio)
        end
      )

      assert {:ok, received} = ElevenLabs.synthesize("Audio test", config: config)
      assert received == raw_audio
    end

    test "returns {:error, {:api_error, 429, _}} on rate limit", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "POST",
        "/v1/text-to-speech/#{config.voice_id}",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(429, Jason.encode!(%{"detail" => "rate limited"}))
        end
      )

      assert {:error, {:api_error, 429, _}} = ElevenLabs.synthesize("Test", config: config)
    end

    test "returns {:error, {:api_error, 401, _}} on unauthorized", %{
      bypass: bypass,
      config: config
    } do
      Bypass.expect_once(
        bypass,
        "POST",
        "/v1/text-to-speech/#{config.voice_id}",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(401, Jason.encode!(%{"detail" => "invalid_api_key"}))
        end
      )

      assert {:error, {:api_error, 401, _}} = ElevenLabs.synthesize("Test", config: config)
    end

    test "returns {:error, _} on network failure", %{bypass: bypass, config: config} do
      Bypass.down(bypass)
      assert {:error, _reason} = ElevenLabs.synthesize("Test", config: config)
    end

    test "cache hit avoids second HTTP request", %{bypass: bypass, config: config} do
      {:ok, cache_pid} = Cache.start_link()

      # Bypass expects exactly ONE call; second call must come from cache
      Bypass.expect_once(
        bypass,
        "POST",
        "/v1/text-to-speech/#{config.voice_id}",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("audio/mpeg")
          |> Plug.Conn.send_resp(200, <<10, 20, 30>>)
        end
      )

      assert {:ok, audio1} =
               ElevenLabs.synthesize("Cached text", config: config, cache: cache_pid)

      assert {:ok, audio2} =
               ElevenLabs.synthesize("Cached text", config: config, cache: cache_pid)

      assert audio1 == audio2
      assert audio1 == <<10, 20, 30>>
    end

    test "different texts produce separate cache entries", %{bypass: bypass, config: config} do
      {:ok, cache_pid} = Cache.start_link()

      Bypass.expect(
        bypass,
        "POST",
        "/v1/text-to-speech/#{config.voice_id}",
        fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          request = Jason.decode!(body)

          audio =
            case request["text"] do
              "Text A" -> <<1, 2>>
              "Text B" -> <<3, 4>>
              _ -> <<0>>
            end

          conn
          |> Plug.Conn.put_resp_content_type("audio/mpeg")
          |> Plug.Conn.send_resp(200, audio)
        end
      )

      assert {:ok, <<1, 2>>} = ElevenLabs.synthesize("Text A", config: config, cache: cache_pid)
      assert {:ok, <<3, 4>>} = ElevenLabs.synthesize("Text B", config: config, cache: cache_pid)
    end

    test "different voice IDs produce separate cache entries", %{bypass: bypass, config: config} do
      {:ok, cache_pid} = Cache.start_link()
      voice_a = "21m00Tcm4TlvDq8ikWAM"
      voice_b = "AZnzlk1XvdvUeBnXmlld"

      Bypass.expect(bypass, "POST", "/v1/text-to-speech/#{voice_a}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("audio/mpeg")
        |> Plug.Conn.send_resp(200, <<1, 1>>)
      end)

      Bypass.expect(bypass, "POST", "/v1/text-to-speech/#{voice_b}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("audio/mpeg")
        |> Plug.Conn.send_resp(200, <<2, 2>>)
      end)

      assert {:ok, <<1, 1>>} =
               ElevenLabs.synthesize("Same text",
                 config: config,
                 voice_id: voice_a,
                 cache: cache_pid
               )

      assert {:ok, <<2, 2>>} =
               ElevenLabs.synthesize("Same text",
                 config: config,
                 voice_id: voice_b,
                 cache: cache_pid
               )
    end
  end
end

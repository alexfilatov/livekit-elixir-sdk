defmodule Livekit.Agents.TTS.DeepgramTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Deepgram TTS, including the two things that are easy to get wrong and hard
  to hear: which endpoint version a voice lives on, and whether the audio
  arrives wrapped in a container.
  """

  alias Livekit.Agents.TTS.Deepgram
  alias Livekit.Agents.TTS.Deepgram.Config

  describe "validate_config/1" do
    test "refuses a missing or blank key" do
      assert {:error, :missing_api_key} = Deepgram.validate_config(%Config{})
      assert {:error, :missing_api_key} = Deepgram.validate_config(%Config{api_key: ""})
    end

    test "accepts a complete config" do
      assert :ok = Deepgram.validate_config(%Config{api_key: "k"})
    end
  end

  describe "defaults" do
    test "raw 48kHz PCM, because that is what the pipeline puts in a room" do
      config = %Config{}

      # A WAV header would arrive as a burst of noise at the start of every
      # utterance — audible, but easy to blame on the network.
      assert config.container == "none"
      assert config.encoding == "linear16"
      assert config.sample_rate == 48_000
    end

    test "the default voice is an Aura-2 one, not a Flux one" do
      # Flux costs $0.045/1k characters against Aura-2's $0.030. A library
      # default that silently picks the most expensive family is a bill
      # nobody chose.
      assert %Config{}.model == "aura-2-thalia-en"
      refute String.starts_with?(%Config{}.model, "flux-")
    end
  end

  describe "endpoint version" do
    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass}
    end

    defp config_for(bypass, model),
      do: %Config{api_key: "k", model: model, base_url: "http://localhost:#{bypass.port}"}

    test "a Flux voice goes to /v2/speak", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v2/speak", fn conn ->
        Plug.Conn.resp(conn, 200, <<1, 2, 3>>)
      end)

      assert {:ok, <<1, 2, 3>>} =
               Deepgram.synthesize("hello", config: config_for(bypass, "flux-colin-en"))
    end

    test "an Aura voice goes to /v1/speak", %{bypass: bypass} do
      # Sending a Flux model to /v1 returns V2_MODEL_ON_V1_SPEAK_ENDPOINT and
      # sending an Aura model to /v2 fails too, so this is not cosmetic.
      Bypass.expect_once(bypass, "POST", "/v1/speak", fn conn ->
        Plug.Conn.resp(conn, 200, <<4, 5>>)
      end)

      assert {:ok, <<4, 5>>} =
               Deepgram.synthesize("hello", config: config_for(bypass, "aura-2-draco-en"))
    end

    test "the format is asked for on the query string", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v2/speak", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["container"] == "none"
        assert conn.query_params["encoding"] == "linear16"
        assert conn.query_params["sample_rate"] == "48000"
        Plug.Conn.resp(conn, 200, <<0>>)
      end)

      Deepgram.synthesize("hello", config: config_for(bypass, "flux-colin-en"))
    end
  end

  describe "failure" do
    test "empty text costs nothing" do
      # A turn that produced nothing to say is normal. Spending a request on it
      # would bill for silence.
      assert {:ok, <<>>} = Deepgram.synthesize("   ", config: %Config{api_key: "k"})
    end

    test "an API error is returned, not raised" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/v1/speak", fn conn ->
        Plug.Conn.resp(conn, 401, ~s({"err_msg":"nope"}))
      end)

      # The default model is an Aura one, so this lands on /v1.
      config = %Config{api_key: "k", base_url: "http://localhost:#{bypass.port}"}
      assert {:error, {:http_error, 401}} = Deepgram.synthesize("hello", config: config)
    end
  end

  describe "against the real Deepgram API" do
    # `:integration`, matching this project's convention in test_helper.exs —
    # `:external` is not in the exclude list, so a test tagged that way runs
    # in CI and fails on the missing key.
    @describetag :integration

    test "Colin speaks, in raw PCM" do
      key = System.get_env("DEEPGRAM_API_KEY")
      if is_nil(key), do: flunk("DEEPGRAM_API_KEY not set")

      {:ok, audio} =
        Deepgram.synthesize("This is a three bedroom semi on Elm Road.",
          config: %Config{api_key: key, model: "aura-2-draco-en"}
        )

      # Real speech, not an error page.
      assert byte_size(audio) > 10_000
      # RIFF here would mean container=none was ignored and the pipeline is
      # about to play a WAV header as audio.
      refute binary_part(audio, 0, 4) == "RIFF"
      # linear16 is 2 bytes per sample; an odd length means it is not PCM16.
      assert rem(byte_size(audio), 2) == 0
    end
  end
end

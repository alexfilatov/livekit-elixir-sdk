defmodule Livekit.Agents.STT.DeepgramTest do
  use ExUnit.Case, async: false

  alias Livekit.Agents.STT.Deepgram
  alias Livekit.Agents.STT.Deepgram.Config
  alias Livekit.Agents.STT.SpeechEvent

  @small_audio :binary.copy(<<0>>, 500)
  @medium_audio :binary.copy(<<0>>, 3000)
  @large_audio :binary.copy(<<0>>, 11_000)

  describe "capabilities/0" do
    test "returns streaming and interim_results as true" do
      caps = Deepgram.capabilities()
      assert caps.streaming == true
      assert caps.interim_results == true
    end

    test "includes diarization support" do
      assert Deepgram.capabilities().diarization == true
    end

    test "languages list is non-empty and includes en-US" do
      langs = Deepgram.capabilities().languages
      assert is_list(langs)
      assert "en-US" in langs
    end
  end

  describe "validate_config/1" do
    test "returns :ok for mock mode regardless of api_key" do
      assert :ok = Deepgram.validate_config(%Config{mock: true})
      assert :ok = Deepgram.validate_config(%Config{mock: true, api_key: nil})
    end

    test "returns {:error, :missing_api_key} for nil api_key in live mode" do
      assert {:error, :missing_api_key} =
               Deepgram.validate_config(%Config{api_key: nil, mock: false})
    end

    test "returns {:error, :missing_api_key} for empty string api_key in live mode" do
      assert {:error, :missing_api_key} =
               Deepgram.validate_config(%Config{api_key: "", mock: false})
    end

    test "returns :ok for valid api_key in live mode" do
      assert :ok = Deepgram.validate_config(%Config{api_key: "dg_test_key", mock: false})
    end
  end

  describe "transcribe/2 mock mode" do
    test "empty audio returns empty transcript" do
      assert {:ok, event} = Deepgram.transcribe(<<>>, config: %Config{mock: true})
      assert %SpeechEvent{type: :final, text: ""} = event
    end

    test "small audio (< 1000 bytes) returns empty text" do
      assert {:ok, event} = Deepgram.transcribe(@small_audio, config: %Config{mock: true})
      assert event.type == :final
      assert event.text == ""
    end

    test "medium audio (1000-4999 bytes) returns 'Hello'" do
      assert {:ok, event} = Deepgram.transcribe(@medium_audio, config: %Config{mock: true})
      assert event.type == :final
      assert event.text == "Hello"
    end

    test "large audio (>= 10000 bytes) returns longer transcript" do
      assert {:ok, event} = Deepgram.transcribe(@large_audio, config: %Config{mock: true})
      assert event.type == :final
      assert String.length(event.text) > 5
    end

    test "language in returned event matches config language" do
      config = %Config{mock: true, language: "fr"}
      {:ok, event} = Deepgram.transcribe(@medium_audio, config: config)
      assert event.language == "fr"
    end

    test "nil api_key with mock: false still returns mock result" do
      config = %Config{api_key: nil, mock: false}

      assert {:ok, %SpeechEvent{type: :final}} =
               Deepgram.transcribe(@medium_audio, config: config)
    end

    test "empty api_key with mock: false still returns mock result" do
      config = %Config{api_key: "", mock: false}

      assert {:ok, %SpeechEvent{type: :final}} =
               Deepgram.transcribe(@medium_audio, config: config)
    end
  end

  describe "transcribe/2 HTTP (Bypass)" do
    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass}
    end

    defp config_for_bypass(bypass) do
      %Config{
        api_key: "test_key",
        mock: false,
        base_url: "http://localhost:#{bypass.port}"
      }
    end

    defp deepgram_response(transcript, confidence \\ 0.99) do
      %{
        "results" => %{
          "channels" => [
            %{
              "alternatives" => [
                %{"transcript" => transcript, "confidence" => confidence}
              ]
            }
          ]
        }
      }
    end

    test "sends POST to /v1/listen and returns final SpeechEvent", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/listen", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(deepgram_response("hello world")))
      end)

      config = config_for_bypass(bypass)
      assert {:ok, event} = Deepgram.transcribe(@large_audio, config: config)
      assert event.type == :final
      assert event.text == "hello world"
    end

    test "extracts confidence from response", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/listen", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(deepgram_response("test", 0.87)))
      end)

      config = config_for_bypass(bypass)
      assert {:ok, event} = Deepgram.transcribe(@large_audio, config: config)
      assert_in_delta event.confidence, 0.87, 0.001
    end

    test "returns empty text for empty transcript", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/listen", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(deepgram_response("")))
      end)

      config = config_for_bypass(bypass)
      assert {:ok, event} = Deepgram.transcribe(@large_audio, config: config)
      assert event.text == ""
      assert event.type == :final
    end

    test "returns error on 401 non-200 status", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/listen", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(401, Jason.encode!(%{"error" => "invalid key"}))
      end)

      config = config_for_bypass(bypass)
      assert {:error, {:api_error, 401, _}} = Deepgram.transcribe(@large_audio, config: config)
    end

    test "sets correct language on returned event", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/listen", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(deepgram_response("bonjour")))
      end)

      config = %{config_for_bypass(bypass) | language: "fr"}
      assert {:ok, event} = Deepgram.transcribe(@large_audio, config: config)
      assert event.language == "fr"
    end
  end
end

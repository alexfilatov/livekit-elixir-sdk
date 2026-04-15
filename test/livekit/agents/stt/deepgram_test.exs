defmodule Livekit.Agents.STT.DeepgramTest do
  use ExUnit.Case, async: false

  alias Livekit.Agents.STT.Deepgram
  alias Livekit.Agents.STT.Deepgram.Config
  alias Livekit.Agents.STT.SpeechEvent

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
    test "returns {:error, :missing_api_key} for nil api_key" do
      assert {:error, :missing_api_key} = Deepgram.validate_config(%Config{api_key: nil})
    end

    test "returns {:error, :missing_api_key} for empty string api_key" do
      assert {:error, :missing_api_key} = Deepgram.validate_config(%Config{api_key: ""})
    end

    test "returns :ok for valid api_key" do
      assert :ok = Deepgram.validate_config(%Config{api_key: "dg_test_key"})
    end

    test "returns {:error, :invalid_sample_rate} for zero sample_rate" do
      assert {:error, :invalid_sample_rate} =
               Deepgram.validate_config(%Config{api_key: "key", sample_rate: 0})
    end
  end

  describe "transcribe/2 missing api_key" do
    test "nil api_key returns {:error, :missing_api_key}" do
      assert {:error, :missing_api_key} =
               Deepgram.transcribe(@large_audio, config: %Config{api_key: nil})
    end

    test "empty api_key returns {:error, :missing_api_key}" do
      assert {:error, :missing_api_key} =
               Deepgram.transcribe(@large_audio, config: %Config{api_key: ""})
    end
  end

  describe "transcribe/2 empty audio" do
    test "empty audio with valid api_key returns empty SpeechEvent" do
      config = %Config{api_key: "test_key"}
      assert {:ok, event} = Deepgram.transcribe(<<>>, config: config)
      assert %SpeechEvent{type: :final, text: ""} = event
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

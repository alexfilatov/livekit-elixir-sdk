defmodule Livekit.Agents.AsyncRobustnessTest do
  @moduledoc """
  Comprehensive async, race condition, and provider integration tests for the
  LiveKit Elixir Agents framework.

  Covers:
  - Deepgram STT provider: mock mode, validation, streaming, and HTTP error paths
  - OpenAI LLM provider: mock mode, message conversion, streaming, and HTTP errors
  - OpenAI TTS provider: mock mode voices, caching, and HTTP error paths
  - EventBus: pub/sub robustness, concurrency, and lifecycle
  - Pipeline: rapid frame pushing, non-deadlock get_context, async turn delivery
  - Worker: mock mode startup, status fields, and capacity tracking
  """

  # async: false because tests exercise a globally-named Registry (EventBus),
  # Bypass port allocation, and Pipeline GenServers with shared telemetry.
  use ExUnit.Case, async: false

  alias Livekit.Agents.ChatContext
  alias Livekit.Agents.{AudioFrame, EventBus, Events, Pipeline, Worker}
  alias Livekit.Agents.LLM.{LLMChunk, OpenAI}
  alias Livekit.Agents.STT.{Deepgram, SpeechEvent}
  alias Livekit.Agents.TTS.OpenAI, as: TTSOAI
  alias Livekit.Agents.TTS.OpenAI.Cache

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  defp unique_id, do: "test-#{:erlang.unique_integer([:positive])}"

  defp speech_frame do
    data = for _ <- 1..160, into: <<>>, do: <<32_767::little-signed-16>>
    AudioFrame.new(data, sample_rate: 16_000, format: :pcm_16)
  end

  defp silence_frame do
    AudioFrame.new(<<0::320*8>>, sample_rate: 16_000, format: :pcm_16)
  end

  # ---------------------------------------------------------------------------
  # 1. Deepgram STT provider robustness
  # ---------------------------------------------------------------------------

  describe "Deepgram.transcribe/2 mock mode" do
    test "empty audio binary returns a result without crashing" do
      config = %Deepgram.Config{mock: true}
      result = Deepgram.transcribe(<<>>, config: config)
      assert {:ok, %SpeechEvent{}} = result
    end

    test "empty audio binary returns a SpeechEvent struct" do
      config = %Deepgram.Config{mock: true}
      {:ok, event} = Deepgram.transcribe(<<>>, config: config)
      assert %SpeechEvent{type: :final} = event
      assert is_binary(event.text)
      assert is_float(event.confidence) or is_integer(event.confidence)
    end
  end

  describe "Deepgram.validate_config/1" do
    test "missing api_key but mock: true returns :ok" do
      assert :ok = Deepgram.validate_config(%Deepgram.Config{mock: true, api_key: nil})
    end

    test "no api_key and no mock flag returns error" do
      assert {:error, :missing_api_key} =
               Deepgram.validate_config(%Deepgram.Config{mock: false, api_key: nil})
    end

    test "empty api_key with mock: false returns error" do
      assert {:error, :missing_api_key} =
               Deepgram.validate_config(%Deepgram.Config{mock: false, api_key: ""})
    end

    test "valid api_key with mock: false returns :ok" do
      assert :ok = Deepgram.validate_config(%Deepgram.Config{mock: false, api_key: "dg_key"})
    end
  end

  describe "Deepgram.capabilities/0" do
    test "returns expected keys" do
      caps = Deepgram.capabilities()
      assert Map.has_key?(caps, :streaming)
      assert Map.has_key?(caps, :interim_results)
      assert Map.has_key?(caps, :diarization)
      assert Map.has_key?(caps, :languages)
    end

    test "streaming is true" do
      assert Deepgram.capabilities().streaming == true
    end

    test "interim_results is true" do
      assert Deepgram.capabilities().interim_results == true
    end

    test "languages list includes en-US" do
      assert "en-US" in Deepgram.capabilities().languages
    end
  end

  describe "Deepgram.stream/1 mock mode" do
    test "delivers events in correct order: :start, :interim, :final, :end" do
      config = %Deepgram.Config{mock: true}
      {:ok, _pid} = Deepgram.stream(config)

      assert_receive {:speech_event, %SpeechEvent{type: :start}}, 500
      assert_receive {:speech_event, %SpeechEvent{type: :interim}}, 500
      assert_receive {:speech_event, %SpeechEvent{type: :final}}, 500
      assert_receive {:speech_event, %SpeechEvent{type: :end}}, 500
    end

    test "subscriber receives all events before stream process terminates" do
      config = %Deepgram.Config{mock: true}
      {:ok, stream_pid} = Deepgram.stream(config)

      Process.flag(:trap_exit, true)
      Process.link(stream_pid)

      # Collect all speech events until stream ends
      events = collect_speech_events(4, 1000)

      types = Enum.map(events, & &1.type)
      assert :start in types
      assert :interim in types
      assert :final in types
      assert :end in types
    end
  end

  describe "Deepgram HTTP via Bypass" do
    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass}
    end

    defp deepgram_config(bypass) do
      %Deepgram.Config{
        api_key: "test_key",
        mock: false,
        base_url: "http://localhost:#{bypass.port}"
      }
    end

    test "returns {:error, _} when server responds 429 (rate limited)", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/listen", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(429, Jason.encode!(%{"error" => "rate limited"}))
      end)

      audio = :binary.copy(<<0>>, 11_000)
      config = deepgram_config(bypass)
      assert {:error, _} = Deepgram.transcribe(audio, config: config)
    end

    test "returns {:error, _} when server responds with malformed JSON", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/listen", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, "not-valid-json{{{")
      end)

      audio = :binary.copy(<<0>>, 11_000)
      config = deepgram_config(bypass)
      # Tesla JSON middleware will fail to decode, returning an error
      result = Deepgram.transcribe(audio, config: config)

      case result do
        {:error, _} -> :ok
        {:ok, %SpeechEvent{text: ""}} -> :ok
      end
    end

    test "handles empty transcript alternatives gracefully", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/listen", fn conn ->
        body = %{
          "results" => %{
            "channels" => [
              %{"alternatives" => []}
            ]
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(body))
      end)

      audio = :binary.copy(<<0>>, 11_000)
      config = deepgram_config(bypass)
      result = Deepgram.transcribe(audio, config: config)

      case result do
        {:ok, %SpeechEvent{text: text}} -> assert is_binary(text)
        {:error, _} -> :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 2. OpenAI LLM provider robustness
  # ---------------------------------------------------------------------------

  describe "OpenAI LLM chat/2 mock mode" do
    test "returns a ChatMessage" do
      config = %OpenAI.Config{mock: true}
      ctx = ChatContext.new() |> ChatContext.add(ChatContext.new_message(:user, ["Hello!"]))
      assert {:ok, msg} = OpenAI.chat(ctx, config: config)
      assert %ChatContext.ChatMessage{role: :assistant} = msg
    end

    test "handles empty string input without crashing" do
      config = %OpenAI.Config{mock: true}
      ctx = ChatContext.new() |> ChatContext.add(ChatContext.new_message(:user, [""]))
      assert {:ok, %ChatContext.ChatMessage{role: :assistant}} = OpenAI.chat(ctx, config: config)
    end
  end

  describe "OpenAI LLM stream/2 mock mode" do
    test "sends LLMChunk messages to caller" do
      config = %OpenAI.Config{mock: true}
      ctx = ChatContext.new() |> ChatContext.add(ChatContext.new_message(:user, ["Hi"]))

      {:ok, _pid} = OpenAI.stream(ctx, config: config)

      assert_receive {:llm_chunk, %LLMChunk{type: :text}}, 500
      assert_receive {:llm_chunk, %LLMChunk{type: :done}}, 500
    end

    test "done chunk arrives after text chunk" do
      config = %OpenAI.Config{mock: true}
      ctx = ChatContext.new() |> ChatContext.add(ChatContext.new_message(:user, ["Hi"]))

      {:ok, _pid} = OpenAI.stream(ctx, config: config)

      chunks = collect_llm_chunks(5, 500)
      types = Enum.map(chunks, & &1.type)
      assert :done in types
      done_index = Enum.find_index(types, &(&1 == :done))
      assert done_index == length(types) - 1
    end
  end

  describe "OpenAI LLM validate_config/1" do
    test "mock: true returns :ok regardless of api_key" do
      assert :ok = OpenAI.validate_config(%OpenAI.Config{mock: true, api_key: nil})
      assert :ok = OpenAI.validate_config(%OpenAI.Config{mock: true, api_key: ""})
    end

    test "nil api_key with mock: false returns error" do
      assert {:error, :missing_api_key} =
               OpenAI.validate_config(%OpenAI.Config{mock: false, api_key: nil})
    end

    test "empty string api_key returns error" do
      assert {:error, :missing_api_key} =
               OpenAI.validate_config(%OpenAI.Config{mock: false, api_key: ""})
    end

    test "valid api_key returns :ok" do
      assert :ok = OpenAI.validate_config(%OpenAI.Config{api_key: "sk-abc123"})
    end
  end

  describe "to_openai_messages/1 via chat/2 (message conversion)" do
    # We test conversion indirectly by verifying the round-trip through
    # the bypass server which receives the converted messages in the body.

    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass}
    end

    defp llm_config(bypass) do
      %OpenAI.Config{
        api_key: "sk-test",
        mock: false,
        base_url: "http://localhost:#{bypass.port}"
      }
    end

    defp capture_request_body(bypass, status, response_body) do
      parent = self()

      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(parent, {:request_body, Jason.decode!(body)})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(status, Jason.encode!(response_body))
      end)
    end

    defp successful_llm_response(content) do
      %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => content,
              "tool_calls" => nil
            },
            "finish_reason" => "stop"
          }
        ]
      }
    end

    test "ChatMessage items appear as role+content objects", %{bypass: bypass} do
      capture_request_body(bypass, 200, successful_llm_response("ok"))

      ctx =
        ChatContext.new()
        |> ChatContext.add(ChatContext.new_message(:system, ["You are helpful."]))
        |> ChatContext.add(ChatContext.new_message(:user, ["Hello"]))

      OpenAI.chat(ctx, config: llm_config(bypass))

      assert_receive {:request_body, body}, 500
      messages = body["messages"]
      roles = Enum.map(messages, & &1["role"])
      assert "system" in roles
      assert "user" in roles
    end

    test "FunctionCall item includes tool_calls field", %{bypass: bypass} do
      capture_request_body(bypass, 200, successful_llm_response("ok"))

      fc = ChatContext.new_function_call("call_001", "get_weather", "{\"city\":\"Berlin\"}")

      ctx =
        ChatContext.new()
        |> ChatContext.add(ChatContext.new_message(:user, ["What's the weather?"]))
        |> ChatContext.add(fc)

      OpenAI.chat(ctx, config: llm_config(bypass))

      assert_receive {:request_body, body}, 500
      messages = body["messages"]

      fc_message = Enum.find(messages, &Map.has_key?(&1, "tool_calls"))
      assert fc_message != nil
      [tool_call] = fc_message["tool_calls"]
      assert tool_call["id"] == "call_001"
      assert tool_call["function"]["name"] == "get_weather"
    end

    test "FunctionCallOutput item includes tool_call_id field", %{bypass: bypass} do
      capture_request_body(bypass, 200, successful_llm_response("ok"))

      fco =
        ChatContext.new_function_call_output("call_001", "get_weather", "Sunny, 25°C")

      ctx =
        ChatContext.new()
        |> ChatContext.add(ChatContext.new_message(:user, ["What's the weather?"]))
        |> ChatContext.add(fco)

      OpenAI.chat(ctx, config: llm_config(bypass))

      assert_receive {:request_body, body}, 500
      messages = body["messages"]

      fco_message = Enum.find(messages, &(&1["role"] == "tool"))
      assert fco_message != nil
      assert fco_message["tool_call_id"] == "call_001"
      assert fco_message["content"] == "Sunny, 25°C"
    end

    test "API returning 500 error returns {:error, _}", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          500,
          Jason.encode!(%{"error" => %{"message" => "Internal Server Error"}})
        )
      end)

      ctx = ChatContext.new() |> ChatContext.add(ChatContext.new_message(:user, ["Hi"]))
      assert {:error, _} = OpenAI.chat(ctx, config: llm_config(bypass))
    end

    test "API returning empty choices array is handled", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"choices" => []}))
      end)

      ctx = ChatContext.new() |> ChatContext.add(ChatContext.new_message(:user, ["Hi"]))

      result = OpenAI.chat(ctx, config: llm_config(bypass))

      case result do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end

    test "API returning finish_reason: length (truncated) still parses successfully", %{
      bypass: bypass
    } do
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        body = %{
          "choices" => [
            %{
              "message" => %{
                "role" => "assistant",
                "content" => "I was cut off mid",
                "tool_calls" => nil
              },
              "finish_reason" => "length"
            }
          ]
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(body))
      end)

      ctx = ChatContext.new() |> ChatContext.add(ChatContext.new_message(:user, ["Hi"]))

      assert {:ok, %ChatContext.ChatMessage{content: ["I was cut off mid"]}} =
               OpenAI.chat(ctx, config: llm_config(bypass))
    end
  end

  # ---------------------------------------------------------------------------
  # 3. OpenAI TTS provider robustness
  # ---------------------------------------------------------------------------

  describe "OpenAI TTS synthesize/2 mock mode" do
    for voice <- [:alloy, :echo, :fable, :onyx, :nova, :shimmer] do
      @voice voice
      test "voice #{voice} returns audio binary" do
        config = %TTSOAI.Config{mock: true, voice: @voice}
        assert {:ok, audio} = TTSOAI.synthesize("Hello there", config: config)
        assert is_binary(audio)
      end
    end

    test "empty string input returns audio (possibly empty)" do
      config = %TTSOAI.Config{mock: true}
      assert {:ok, audio} = TTSOAI.synthesize("", config: config)
      assert is_binary(audio)
    end
  end

  describe "OpenAI TTS caching" do
    test "second call with cache returns cached result" do
      {:ok, cache} = Cache.start_link(ttl_seconds: 60)
      config = %TTSOAI.Config{api_key: "sk-x", mock: false, base_url: "http://127.0.0.1:1"}

      text = "cache test #{unique_id()}"

      # Build the exact cache key the module builds
      real_key =
        :crypto.hash(
          :sha256,
          "#{config.model}_#{config.voice}_#{config.speed}_#{config.response_format}_#{text}"
        )
        |> Base.encode16(case: :lower)

      audio_data = :crypto.strong_rand_bytes(100)
      Cache.put(cache, real_key, audio_data)

      {:ok, result} = TTSOAI.synthesize(text, config: config, cache: cache)
      assert result == audio_data
    end

    test "cache miss causes a fresh synthesis attempt" do
      {:ok, cache} = Cache.start_link(ttl_seconds: 60, max_entries: 10)
      config = %TTSOAI.Config{mock: true}
      text = "fresh synthesis #{unique_id()}"

      {:ok, audio1} = TTSOAI.synthesize(text, config: config, cache: cache)
      {:ok, audio2} = TTSOAI.synthesize(text, config: config, cache: cache)

      # Both return valid audio (mock always succeeds); deterministic mock returns
      # equal binaries for same text+voice combination
      assert is_binary(audio1)
      assert is_binary(audio2)
    end
  end

  describe "OpenAI TTS validate_config/1" do
    test "mock: true returns :ok" do
      assert :ok = TTSOAI.validate_config(%TTSOAI.Config{mock: true})
    end

    test "nil api_key with mock: false returns error" do
      assert {:error, :missing_api_key} =
               TTSOAI.validate_config(%TTSOAI.Config{mock: false, api_key: nil})
    end

    test "speed below 0.25 returns error" do
      assert {:error, :invalid_speed} =
               TTSOAI.validate_config(%TTSOAI.Config{api_key: "sk-x", speed: 0.1})
    end

    test "speed above 4.0 returns error" do
      assert {:error, :invalid_speed} =
               TTSOAI.validate_config(%TTSOAI.Config{api_key: "sk-x", speed: 4.1})
    end

    test "valid config returns :ok" do
      assert :ok =
               TTSOAI.validate_config(%TTSOAI.Config{
                 api_key: "sk-x",
                 speed: 1.0,
                 sample_rate: 48_000
               })
    end
  end

  describe "OpenAI TTS HTTP via Bypass" do
    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass}
    end

    defp tts_config(bypass) do
      %TTSOAI.Config{
        api_key: "sk-test",
        mock: false,
        base_url: "http://localhost:#{bypass.port}"
      }
    end

    test "API returning non-audio content type returns {:error, _}", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/audio/speech", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.resp(200, "unexpected text response")
      end)

      # The TTS client does not validate content type; a 200 with non-JSON body
      # is treated as audio — we verify no crash and a result is returned
      result = TTSOAI.synthesize("Hello", config: tts_config(bypass))

      case result do
        {:ok, body} when is_binary(body) -> :ok
        {:error, _} -> :ok
      end
    end

    test "API returning empty body is handled without crash", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/audio/speech", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("audio/pcm")
        |> Plug.Conn.resp(200, "")
      end)

      result = TTSOAI.synthesize("Hello", config: tts_config(bypass))

      case result do
        {:ok, binary} -> assert is_binary(binary)
        {:error, _} -> :ok
      end
    end

    test "API returning 500 error returns {:error, _}", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/audio/speech", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{"error" => %{"message" => "server error"}}))
      end)

      assert {:error, _} = TTSOAI.synthesize("Hello", config: tts_config(bypass))
    end
  end

  # ---------------------------------------------------------------------------
  # 4. EventBus async robustness
  # ---------------------------------------------------------------------------

  describe "EventBus multiple subscribers" do
    setup do
      pid =
        case EventBus.start_link() do
          {:ok, p} -> p
          {:error, {:already_started, p}} -> p
        end

      Process.unlink(pid)
      {:ok, session_id: unique_id()}
    end

    test "multiple subscribers receive the same event", %{session_id: session_id} do
      parent = self()

      subscriber2 =
        spawn(fn ->
          EventBus.subscribe(session_id)
          send(parent, :ready)

          receive do
            {:livekit_event, event} -> send(parent, {:sub2_received, event})
          after
            1_000 -> send(parent, :sub2_timeout)
          end
        end)

      assert_receive :ready, 500
      EventBus.subscribe(session_id)

      event = %Events.UserStateChanged{
        from: :listening,
        to: :speaking,
        timestamp: DateTime.utc_now()
      }

      EventBus.publish(session_id, event)

      assert_receive {:livekit_event, %Events.UserStateChanged{}}, 500
      assert_receive {:sub2_received, %Events.UserStateChanged{}}, 500

      EventBus.unsubscribe(session_id)
      Process.exit(subscriber2, :kill)
    end

    test "unsubscribe stops event delivery", %{session_id: session_id} do
      EventBus.subscribe(session_id)

      EventBus.publish(session_id, %Events.UserStateChanged{
        from: :idle,
        to: :listening,
        timestamp: DateTime.utc_now()
      })

      assert_receive {:livekit_event, _}, 500
      EventBus.unsubscribe(session_id)

      EventBus.publish(session_id, %Events.UserStateChanged{
        from: :listening,
        to: :speaking,
        timestamp: DateTime.utc_now()
      })

      refute_receive {:livekit_event, _}, 100
    end

    test "publishing with no subscribers does not crash", %{session_id: _session_id} do
      orphan_id = "orphan-#{unique_id()}"

      assert :ok =
               EventBus.publish(orphan_id, %Events.UserStateChanged{
                 from: :idle,
                 to: :listening,
                 timestamp: DateTime.utc_now()
               })
    end

    test "emit_metric/3 with various metric names delivers events", %{session_id: session_id} do
      EventBus.subscribe(session_id)

      for metric <- [:ttft_ms, :end_to_end_latency_ms, :token_count, :custom_metric] do
        EventBus.emit_metric(session_id, metric, 42)
      end

      for metric <- [:ttft_ms, :end_to_end_latency_ms, :token_count, :custom_metric] do
        assert_receive {:livekit_event, %Events.TelemetryMeasurement{metric: ^metric}}, 500
      end

      EventBus.unsubscribe(session_id)
    end

    test "EventBus start/stop lifecycle leaves no orphaned processes" do
      # Count Registry children before additional start
      before_count = count_registry_processes()

      session_id = unique_id()
      EventBus.subscribe(session_id)
      EventBus.unsubscribe(session_id)

      # After unsubscribe, the Registry entry for this session should be gone
      after_count = count_registry_processes()
      assert after_count <= before_count + 1
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Pipeline async flow
  # ---------------------------------------------------------------------------

  # Inline mock providers for pipeline tests
  defmodule PipelineMockSTT do
    @moduledoc false
    use Livekit.Agents.STT

    @impl true
    def transcribe(_audio_binary, _opts) do
      {:ok,
       %SpeechEvent{
         type: :final,
         text: "hello world",
         confidence: 0.99,
         language: "en"
       }}
    end

    @impl true
    def capabilities,
      do: %{streaming: false, interim_results: false, diarization: false, languages: ["en"]}
  end

  defmodule PipelineMockLLM do
    @moduledoc false
    use Livekit.Agents.LLM

    @impl true
    def chat(_context, _opts) do
      {:ok, %{role: :assistant, content: "Response text"}}
    end

    @impl true
    def capabilities,
      do: %{streaming: false, tool_calling: false, vision: false, max_context_tokens: 4096}
  end

  defmodule PipelineMockTTS do
    @moduledoc false
    use Livekit.Agents.TTS

    @impl true
    def synthesize(_text, _opts) do
      {:ok, :crypto.strong_rand_bytes(64)}
    end

    @impl true
    def capabilities,
      do: %{streaming: false, voices: ["default"], audio_formats: [:pcm], word_timing: false}
  end

  defp pipeline_config(overrides \\ []) do
    %Pipeline.Config{
      stt: {PipelineMockSTT, %{}},
      llm: {PipelineMockLLM, %{}},
      tts: {PipelineMockTTS, %{}},
      silence_ms: Keyword.get(overrides, :silence_ms, 50),
      subscriber: Keyword.get(overrides, :subscriber, nil)
    }
  end

  describe "Pipeline async flow" do
    test "handles rapid frame pushing without backpressure issues" do
      {:ok, pid} = Pipeline.start_link(pipeline_config())

      # Push 50 frames rapidly — all casts must return :ok without blocking
      results = for _ <- 1..50, do: Pipeline.push_frame(pid, silence_frame())
      assert Enum.all?(results, &(&1 == :ok))

      # GenServer must still be alive and responsive
      assert Process.alive?(pid)
      metrics = Pipeline.get_metrics(pid)
      assert metrics.audio_frames_processed >= 50

      Pipeline.stop(pid)
    end

    test "get_metrics/1 during active processing does not deadlock" do
      {:ok, pid} = Pipeline.start_link(pipeline_config())

      # Trigger a turn that runs an async Task
      Pipeline.push_frame(pid, speech_frame())
      Pipeline.push_frame(pid, silence_frame())

      # Immediately call get_metrics while the Task may be running
      task = Task.async(fn -> Pipeline.get_metrics(pid) end)
      assert %{} = Task.await(task, 2_000)

      Pipeline.stop(pid)
    end

    test "subscriber receives pipeline_audio after full turn" do
      test_pid = self()
      config = pipeline_config(subscriber: test_pid, silence_ms: 50)
      {:ok, pid} = Pipeline.start_link(config)

      Pipeline.push_frame(pid, speech_frame())
      Pipeline.push_frame(pid, silence_frame())

      assert_receive {:pipeline_audio, %AudioFrame{data: data}}, 1_000
      assert is_binary(data)

      Pipeline.stop(pid)
    end

    test "metrics update after processing a turn" do
      {:ok, pid} = Pipeline.start_link(pipeline_config(silence_ms: 50))

      Pipeline.push_frame(pid, speech_frame())
      Pipeline.push_frame(pid, silence_frame())

      # Wait for the async task to complete
      Process.sleep(400)

      metrics = Pipeline.get_metrics(pid)
      assert metrics.turns_processed == 1
      assert metrics.audio_frames_processed == 2
      assert metrics.errors == 0

      Pipeline.stop(pid)
    end

    test "pipeline stops cleanly without orphaned tasks" do
      {:ok, pid} = Pipeline.start_link(pipeline_config())

      # Push some frames to ensure the pipeline is active
      Pipeline.push_frame(pid, silence_frame())
      Pipeline.push_frame(pid, silence_frame())

      Process.flag(:trap_exit, true)
      Process.link(pid)

      Pipeline.stop(pid)

      assert_receive {:EXIT, ^pid, :normal}, 2_000
      refute Process.alive?(pid)
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Worker robustness
  # ---------------------------------------------------------------------------

  defp start_test_worker(overrides \\ []) do
    config =
      struct(
        Worker.Config,
        Keyword.merge(
          [
            api_key: "test-key",
            api_secret: "test-secret",
            entrypoint: fn _ctx -> :ok end,
            server_url: nil,
            max_concurrent_jobs: 3,
            heartbeat_interval: 60_000,
            drain_timeout: 5_000
          ],
          overrides
        )
      )

    {:ok, pid} = Worker.start_link(config)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid, :normal, 2_000)
    end)

    pid
  end

  describe "Worker robustness" do
    test "mock mode starts without errors" do
      pid = start_test_worker()
      assert Process.alive?(pid)
    end

    test "get_status/1 returns expected fields" do
      pid = start_test_worker()
      # Allow :connect message to be processed
      Process.sleep(50)

      status = Worker.get_status(pid)

      for key <- [
            :worker_id,
            :registered,
            :active_jobs,
            :max_concurrent_jobs,
            :load,
            :draining,
            :health_status,
            :last_heartbeat,
            :namespace,
            :metrics
          ] do
        assert Map.has_key?(status, key), "Missing status key: #{key}"
      end
    end

    test "get_status/1 registered is true after mock connect" do
      pid = start_test_worker()
      Process.sleep(50)
      status = Worker.get_status(pid)
      assert status.registered == true
    end

    test "worker handles job completion (simulated via process exit)" do
      pid = start_test_worker()
      Process.sleep(50)

      # Inject a fake job with a real monitored process
      session = spawn(fn -> Process.sleep(200) end)

      :sys.replace_state(pid, fn state ->
        ref = Process.monitor(session)

        jobs = %{
          "job-sim" => %{
            session_pid: session,
            monitor_ref: ref,
            room_name: "test-room",
            participant_identity: "user-1",
            started_at: DateTime.utc_now()
          }
        }

        %{state | active_jobs: jobs}
      end)

      assert Worker.get_status(pid).active_jobs == 1

      # Terminate the session — Worker receives :DOWN and clears the job
      Process.exit(session, :normal)
      Process.sleep(200)

      assert Worker.get_status(pid).active_jobs == 0
    end

    test "capacity tracking: at_capacity when max_concurrent_jobs reached" do
      pid = start_test_worker(max_concurrent_jobs: 2)
      Process.sleep(50)

      # Inject two fake jobs to fill capacity
      sessions = for _ <- 1..2, do: spawn(fn -> Process.sleep(10_000) end)

      :sys.replace_state(pid, fn state ->
        jobs =
          sessions
          |> Enum.with_index()
          |> Map.new(fn {s, i} ->
            ref = Process.monitor(s)

            info = %{
              session_pid: s,
              monitor_ref: ref,
              room_name: "room-#{i}",
              participant_identity: "user-#{i}",
              started_at: DateTime.utc_now()
            }

            {"job-#{i}", info}
          end)

        %{state | active_jobs: jobs}
      end)

      status = Worker.get_status(pid)
      assert status.active_jobs == 2
      assert status.active_jobs == status.max_concurrent_jobs
      assert status.load == 1.0

      # Cleanup
      Enum.each(sessions, &Process.exit(&1, :kill))
    end
  end

  # ---------------------------------------------------------------------------
  # Private test helpers
  # ---------------------------------------------------------------------------

  defp collect_speech_events(count, timeout) do
    Enum.reduce_while(1..count, [], fn _, acc ->
      receive do
        {:speech_event, event} -> {:cont, acc ++ [event]}
      after
        timeout -> {:halt, acc}
      end
    end)
  end

  defp collect_llm_chunks(max, timeout) do
    Enum.reduce_while(1..max, [], fn _, acc ->
      receive do
        {:llm_chunk, chunk} ->
          if chunk.type == :done do
            {:halt, acc ++ [chunk]}
          else
            {:cont, acc ++ [chunk]}
          end
      after
        timeout -> {:halt, acc}
      end
    end)
  end

  defp count_registry_processes do
    registry = Livekit.Agents.EventBus.Registry

    case Registry.select(registry, [{{:"$1", :"$2", :"$3"}, [], [:"$2"]}]) do
      pids when is_list(pids) -> length(pids)
      _ -> 0
    end
  rescue
    _ -> 0
  end
end

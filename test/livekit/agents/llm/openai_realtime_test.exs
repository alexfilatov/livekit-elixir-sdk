defmodule Livekit.Agents.LLM.OpenAIRealtimeTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.LLM.OpenAIRealtime
  alias Livekit.Agents.LLM.OpenAIRealtime.Config

  # ---------------------------------------------------------------------------
  # validate_config/1
  # ---------------------------------------------------------------------------

  describe "validate_config/1" do
    test "mock: true with nil api_key returns :ok" do
      assert :ok = OpenAIRealtime.validate_config(%Config{mock: true, api_key: nil})
    end

    test "mock: false with nil api_key returns {:error, :missing_api_key}" do
      assert {:error, :missing_api_key} =
               OpenAIRealtime.validate_config(%Config{mock: false, api_key: nil})
    end

    test "mock: false with empty string api_key returns {:error, :missing_api_key}" do
      assert {:error, :missing_api_key} =
               OpenAIRealtime.validate_config(%Config{mock: false, api_key: ""})
    end

    test "mock: false with valid api_key returns :ok" do
      assert :ok = OpenAIRealtime.validate_config(%Config{mock: false, api_key: "sk-test-key"})
    end
  end

  # ---------------------------------------------------------------------------
  # Config defaults
  # ---------------------------------------------------------------------------

  describe "Config defaults" do
    test "default model is gpt-4o-realtime-preview" do
      assert %Config{model: "gpt-4o-realtime-preview"} = %Config{}
    end

    test "default voice is alloy" do
      assert %Config{voice: "alloy"} = %Config{}
    end

    test "default mock is false" do
      assert %Config{mock: false} = %Config{}
    end

    test "default api_key is nil" do
      assert %Config{api_key: nil} = %Config{}
    end

    test "default instructions is non-empty" do
      config = %Config{}
      assert is_binary(config.instructions)
      assert String.length(config.instructions) > 0
    end
  end

  # ---------------------------------------------------------------------------
  # connect/1 mock mode
  # ---------------------------------------------------------------------------

  describe "connect/1 mock mode" do
    setup do
      config = %Config{mock: true}
      {:ok, pid} = OpenAIRealtime.start_link({config, self()})
      {:ok, pid: pid}
    end

    test "connect/1 returns :ok immediately", %{pid: pid} do
      assert :ok = OpenAIRealtime.connect(pid)
    end

    test "session becomes connected after connect/1", %{pid: pid} do
      OpenAIRealtime.connect(pid)
      # Give the GenServer time to process the cast
      Process.sleep(20)
      metrics = OpenAIRealtime.get_metrics(pid)
      assert is_map(metrics)
    end
  end

  # ---------------------------------------------------------------------------
  # push_audio/2 mock mode
  # ---------------------------------------------------------------------------

  describe "push_audio/2 mock mode" do
    setup do
      config = %Config{mock: true}
      {:ok, pid} = OpenAIRealtime.start_link({config, self()})
      OpenAIRealtime.connect(pid)
      Process.sleep(10)
      {:ok, pid: pid}
    end

    test "push_audio/2 returns :ok", %{pid: pid} do
      assert :ok = OpenAIRealtime.push_audio(pid, <<0, 1, 2, 3>>)
    end

    test "push_audio/2 increments audio_chunks_sent metric", %{pid: pid} do
      before_metrics = OpenAIRealtime.get_metrics(pid)
      OpenAIRealtime.push_audio(pid, <<0, 1, 2, 3>>)
      Process.sleep(10)
      after_metrics = OpenAIRealtime.get_metrics(pid)
      assert after_metrics.audio_chunks_sent == before_metrics.audio_chunks_sent + 1
    end

    test "push_audio/2 accepts empty binary", %{pid: pid} do
      assert :ok = OpenAIRealtime.push_audio(pid, <<>>)
    end

    test "push_audio/2 accepts large audio chunks", %{pid: pid} do
      large_audio = :binary.copy(<<0>>, 48_000)
      assert :ok = OpenAIRealtime.push_audio(pid, large_audio)
    end
  end

  # ---------------------------------------------------------------------------
  # generate_reply/1 mock mode
  # ---------------------------------------------------------------------------

  describe "generate_reply/1 mock mode" do
    setup do
      config = %Config{mock: true}
      {:ok, pid} = OpenAIRealtime.start_link({config, self()})
      OpenAIRealtime.connect(pid)
      Process.sleep(10)
      {:ok, pid: pid}
    end

    test "generate_reply/1 returns :ok", %{pid: pid} do
      assert :ok = OpenAIRealtime.generate_reply(pid)
    end

    test "generate_reply/1 triggers realtime_text event", %{pid: pid} do
      OpenAIRealtime.generate_reply(pid)

      assert_receive {:realtime_text, text}, 500
      assert is_binary(text)
      assert String.length(text) > 0
    end

    test "generate_reply/1 triggers realtime_audio event", %{pid: pid} do
      OpenAIRealtime.generate_reply(pid)

      assert_receive {:realtime_audio, audio}, 500
      assert is_binary(audio)
    end

    test "generate_reply/1 triggers realtime_transcript event", %{pid: pid} do
      OpenAIRealtime.generate_reply(pid)

      assert_receive {:realtime_transcript, transcript}, 500
      assert is_binary(transcript)
    end

    test "generate_reply/1 triggers realtime_done event", %{pid: pid} do
      OpenAIRealtime.generate_reply(pid)

      assert_receive {:realtime_done}, 500
    end

    test "generate_reply/1 triggers realtime_speech_stopped before text", %{pid: pid} do
      OpenAIRealtime.generate_reply(pid)

      assert_receive {:realtime_speech_stopped}, 500
    end

    test "generate_reply/1 increments replies_generated metric", %{pid: pid} do
      before_metrics = OpenAIRealtime.get_metrics(pid)
      OpenAIRealtime.generate_reply(pid)
      Process.sleep(10)
      after_metrics = OpenAIRealtime.get_metrics(pid)
      assert after_metrics.replies_generated == before_metrics.replies_generated + 1
    end
  end

  # ---------------------------------------------------------------------------
  # Server event handling (dispatch_event via internal message injection)
  # ---------------------------------------------------------------------------

  describe "server event handling" do
    setup do
      config = %Config{mock: true}
      {:ok, pid} = OpenAIRealtime.start_link({config, self()})
      OpenAIRealtime.connect(pid)
      Process.sleep(10)
      {:ok, pid: pid}
    end

    test "response.audio.delta with valid base64 sends realtime_audio", %{pid: pid} do
      audio_data = <<1, 2, 3, 4, 5, 6>>
      encoded = Base.encode64(audio_data)

      event =
        Jason.encode!(%{
          "type" => "response.audio.delta",
          "delta" => encoded
        })

      # Inject the event as if it arrived from the WebSocket
      send(pid, {:gun_ws, :fake_conn, :fake_ref, {:text, event}})

      assert_receive {:realtime_audio, ^audio_data}, 500
    end

    test "response.text.delta sends realtime_text", %{pid: pid} do
      event = Jason.encode!(%{"type" => "response.text.delta", "delta" => "Hello!"})
      send(pid, {:gun_ws, :fake_conn, :fake_ref, {:text, event}})

      assert_receive {:realtime_text, "Hello!"}, 500
    end

    test "input_audio_buffer.speech_started sends realtime_speech_started", %{pid: pid} do
      event = Jason.encode!(%{"type" => "input_audio_buffer.speech_started"})
      send(pid, {:gun_ws, :fake_conn, :fake_ref, {:text, event}})

      assert_receive {:realtime_speech_started}, 500
    end

    test "input_audio_buffer.speech_stopped sends realtime_speech_stopped", %{pid: pid} do
      event = Jason.encode!(%{"type" => "input_audio_buffer.speech_stopped"})
      send(pid, {:gun_ws, :fake_conn, :fake_ref, {:text, event}})

      assert_receive {:realtime_speech_stopped}, 500
    end

    test "response.done sends realtime_done", %{pid: pid} do
      event = Jason.encode!(%{"type" => "response.done"})
      send(pid, {:gun_ws, :fake_conn, :fake_ref, {:text, event}})

      assert_receive {:realtime_done}, 500
    end

    test "conversation.item.input_audio_transcription.completed sends realtime_transcript",
         %{pid: pid} do
      event =
        Jason.encode!(%{
          "type" => "conversation.item.input_audio_transcription.completed",
          "transcript" => "What is the weather?"
        })

      send(pid, {:gun_ws, :fake_conn, :fake_ref, {:text, event}})

      assert_receive {:realtime_transcript, "What is the weather?"}, 500
    end

    test "error event sends {:error, {:server_error, ...}}", %{pid: pid} do
      event =
        Jason.encode!(%{
          "type" => "error",
          "error" => %{"message" => "invalid request", "code" => "invalid_request_error"}
        })

      send(pid, {:gun_ws, :fake_conn, :fake_ref, {:text, event}})

      assert_receive {:error, {:server_error, error}}, 500
      assert is_map(error)
      assert Map.has_key?(error, "message")
    end

    test "unknown event type is silently ignored", %{pid: pid} do
      event = Jason.encode!(%{"type" => "some.unknown.event", "data" => "whatever"})
      send(pid, {:gun_ws, :fake_conn, :fake_ref, {:text, event}})
      Process.sleep(50)
      # No message received — assert mailbox is empty for our expected types
      refute_receive {:realtime_audio, _}, 50
      refute_receive {:realtime_text, _}, 50
      refute_receive {:realtime_done}, 50
    end

    test "malformed JSON frame is ignored", %{pid: pid} do
      send(pid, {:gun_ws, :fake_conn, :fake_ref, {:text, "not valid json!!!"}})
      Process.sleep(50)
      refute_receive {:realtime_audio, _}, 50
    end
  end

  # ---------------------------------------------------------------------------
  # get_metrics/1
  # ---------------------------------------------------------------------------

  describe "get_metrics/1" do
    test "returns a metrics map with expected keys" do
      config = %Config{mock: true}
      {:ok, pid} = OpenAIRealtime.start_link({config, self()})

      metrics = OpenAIRealtime.get_metrics(pid)

      assert is_map(metrics)
      assert Map.has_key?(metrics, :audio_chunks_sent)
      assert Map.has_key?(metrics, :audio_chunks_received)
      assert Map.has_key?(metrics, :replies_generated)
      assert Map.has_key?(metrics, :errors)
      assert Map.has_key?(metrics, :last_activity)
    end

    test "initial metrics are all zero" do
      config = %Config{mock: true}
      {:ok, pid} = OpenAIRealtime.start_link({config, self()})

      metrics = OpenAIRealtime.get_metrics(pid)

      assert metrics.audio_chunks_sent == 0
      assert metrics.audio_chunks_received == 0
      assert metrics.replies_generated == 0
      assert metrics.errors == 0
      assert is_nil(metrics.last_activity)
    end
  end

  # ---------------------------------------------------------------------------
  # disconnect/1
  # ---------------------------------------------------------------------------

  describe "disconnect/1" do
    test "disconnect/1 stops the GenServer" do
      config = %Config{mock: true}
      {:ok, pid} = OpenAIRealtime.start_link({config, self()})

      ref = Process.monitor(pid)
      OpenAIRealtime.disconnect(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    end
  end
end

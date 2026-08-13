defmodule Livekit.Agents.LLM.OpenAIRealtimeTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.LLM.OpenAIRealtime
  alias Livekit.Agents.LLM.OpenAIRealtime.Config

  # ---------------------------------------------------------------------------
  # validate_config/1
  # ---------------------------------------------------------------------------

  describe "validate_config/1" do
    test "nil api_key returns {:error, :missing_api_key}" do
      assert {:error, :missing_api_key} =
               OpenAIRealtime.validate_config(%Config{api_key: nil})
    end

    test "empty string api_key returns {:error, :missing_api_key}" do
      assert {:error, :missing_api_key} =
               OpenAIRealtime.validate_config(%Config{api_key: ""})
    end

    test "valid api_key returns :ok" do
      assert :ok = OpenAIRealtime.validate_config(%Config{api_key: "sk-test-key"})
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
  # start_link/1 and get_metrics/1
  # ---------------------------------------------------------------------------

  describe "start_link/1" do
    test "starts a GenServer process with a valid api_key" do
      config = %Config{api_key: "sk-test"}
      assert {:ok, pid} = OpenAIRealtime.start_link({config, self()})
      assert is_pid(pid)
      OpenAIRealtime.disconnect(pid)
    end
  end

  describe "get_metrics/1" do
    test "returns a metrics map with expected keys" do
      config = %Config{api_key: "sk-test"}
      {:ok, pid} = OpenAIRealtime.start_link({config, self()})

      metrics = OpenAIRealtime.get_metrics(pid)

      assert is_map(metrics)
      assert Map.has_key?(metrics, :audio_chunks_sent)
      assert Map.has_key?(metrics, :audio_chunks_received)
      assert Map.has_key?(metrics, :replies_generated)
      assert Map.has_key?(metrics, :errors)
      assert Map.has_key?(metrics, :last_activity)

      OpenAIRealtime.disconnect(pid)
    end

    test "initial metrics are all zero" do
      config = %Config{api_key: "sk-test"}
      {:ok, pid} = OpenAIRealtime.start_link({config, self()})

      metrics = OpenAIRealtime.get_metrics(pid)

      assert metrics.audio_chunks_sent == 0
      assert metrics.audio_chunks_received == 0
      assert metrics.replies_generated == 0
      assert metrics.errors == 0
      assert is_nil(metrics.last_activity)

      OpenAIRealtime.disconnect(pid)
    end
  end

  # ---------------------------------------------------------------------------
  # disconnect/1
  # ---------------------------------------------------------------------------

  describe "disconnect/1" do
    test "disconnect/1 stops the GenServer" do
      config = %Config{api_key: "sk-test"}
      {:ok, pid} = OpenAIRealtime.start_link({config, self()})

      ref = Process.monitor(pid)
      OpenAIRealtime.disconnect(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    end
  end

  # ---------------------------------------------------------------------------
  # Server event handling (dispatch_event via internal message injection)
  # The GenServer handles {:gun_ws, conn, ref, {:text, frame}} events.
  # We inject them directly using send/2 to test dispatch_event logic
  # without needing a real WebSocket connection.
  # Note: the conn guard checks state.conn — since connected is false and
  # conn is nil, we use the catch-all handle_info path for injected frames.
  # To bypass the conn guard, we use a connected state by sending gun_upgrade first.
  # ---------------------------------------------------------------------------

  describe "server event handling via injected gun_ws frames" do
    setup do
      # Start with a valid api_key; the process won't actually connect since
      # we never call connect/1. We use :sys.replace_state/2 to directly set
      # conn: :fake_conn and connected: true so that gun_ws frame pattern
      # matches succeed (they pin-match on state.conn).
      config = %Config{api_key: "sk-test"}
      {:ok, pid} = OpenAIRealtime.start_link({config, self()})

      :sys.replace_state(pid, fn state ->
        %{state | conn: :fake_conn, connected: true}
      end)

      {:ok, pid: pid}
    end

    test "response.audio.delta with valid base64 sends realtime_audio", %{pid: pid} do
      audio_data = <<1, 2, 3, 4, 5, 6>>
      encoded = Base.encode64(audio_data)

      event = Jason.encode!(%{"type" => "response.audio.delta", "delta" => encoded})
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
end

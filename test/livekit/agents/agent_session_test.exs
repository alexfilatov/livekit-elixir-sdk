defmodule AgentSessionTest.MockNIF do
  @moduledoc false

  def room_connect(_url, _token, _pid), do: {:ok, make_ref()}
  def room_disconnect(_room_ref), do: :ok
  def audio_subscribe(_room_ref, _track_sid, _pid), do: {:ok, make_ref()}
  def audio_publish_frame(_room_ref, _data, _sr, _ch), do: :ok
end

defmodule AgentSessionTest.MockSTT do
  @moduledoc false

  @behaviour Livekit.Agents.STT

  @impl true
  def transcribe(_audio, _opts) do
    {:ok, %Livekit.Agents.STT.SpeechEvent{text: "hi", confidence: 1.0}}
  end

  @impl true
  def capabilities, do: %{streaming: false}
end

defmodule AgentSessionTest.MockLLM do
  @moduledoc false

  @behaviour Livekit.Agents.LLM

  @impl true
  def chat(_ctx, _opts), do: {:ok, %{role: :assistant, content: ["hello"]}}

  @impl true
  def capabilities, do: %{streaming: false, tool_calling: false}
end

defmodule AgentSessionTest.MockTTS do
  @moduledoc false

  @behaviour Livekit.Agents.TTS

  @impl true
  def synthesize(_text, _opts), do: {:ok, <<0, 0, 0, 0>>}

  @impl true
  def capabilities, do: %{streaming: false, voice_selection: false}
end

defmodule Livekit.Agents.AgentSessionTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Livekit.Agents.{AgentSession, Pipeline}

  defp mock_pipeline_config do
    %Pipeline.Config{
      stt: {AgentSessionTest.MockSTT, %{mock: true}},
      llm: {AgentSessionTest.MockLLM, %{mock: true}},
      tts: {AgentSessionTest.MockTTS, %{mock: true}}
    }
  end

  defp mock_config(overrides \\ []) do
    base = %AgentSession.Config{
      room_name: "test-room",
      participant_identity: "agent",
      server_url: nil,
      api_key: nil,
      api_secret: nil,
      pipeline_config: nil
    }

    Enum.reduce(overrides, base, fn {key, val}, acc -> Map.put(acc, key, val) end)
  end

  # ---------------------------------------------------------------------------
  # Mock mode tests
  # ---------------------------------------------------------------------------

  describe "mock mode (server_url nil)" do
    test "start_link returns {:ok, pid}" do
      config = mock_config()
      assert {:ok, pid} = AgentSession.start_link(config)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "connect_to_room returns :ok and room_connected becomes true" do
      config = mock_config(room_name: nil)
      {:ok, pid} = AgentSession.start_link(config)

      assert :ok = AgentSession.connect_to_room(pid)
      status = AgentSession.get_status(pid)
      assert status.room_connected == true

      GenServer.stop(pid)
    end

    test "disconnect_from_room sets room_connected to false" do
      config = mock_config(room_name: nil)
      {:ok, pid} = AgentSession.start_link(config)

      AgentSession.connect_to_room(pid)
      assert AgentSession.get_status(pid).room_connected == true

      AgentSession.disconnect_from_room(pid)
      assert AgentSession.get_status(pid).room_connected == false

      GenServer.stop(pid)
    end

    test "get_status map contains required keys" do
      config = mock_config(room_name: nil)
      {:ok, pid} = AgentSession.start_link(config)

      status = AgentSession.get_status(pid)

      assert Map.has_key?(status, :room_connected)
      assert Map.has_key?(status, :room_name)
      assert Map.has_key?(status, :participant_identity)
      assert Map.has_key?(status, :participants_count)
      assert Map.has_key?(status, :metrics)

      GenServer.stop(pid)
    end

    test "room_name: nil does not trigger auto_connect" do
      config = mock_config(room_name: nil)
      {:ok, pid} = AgentSession.start_link(config)

      # Give enough time for auto_connect to fire if it were going to
      Process.sleep(50)
      status = AgentSession.get_status(pid)
      assert status.room_connected == false

      GenServer.stop(pid)
    end

    test "get_status returns correct room_name and participant_identity" do
      config = mock_config(room_name: "my-room", participant_identity: "my-agent")
      {:ok, pid} = AgentSession.start_link(config)

      status = AgentSession.get_status(pid)
      assert status.room_name == "my-room"
      assert status.participant_identity == "my-agent"

      GenServer.stop(pid)
    end
  end

  # ---------------------------------------------------------------------------
  # Real mode tests (MockNIF injected)
  # ---------------------------------------------------------------------------

  describe "real mode (server_url set, MockNIF injected)" do
    defp real_config do
      mock_config(
        server_url: "wss://test.livekit.io",
        api_key: "test-key",
        api_secret: "test-secret",
        room_name: nil,
        pipeline_config: mock_pipeline_config(),
        nif_module: AgentSessionTest.MockNIF
      )
    end

    test "connect_to_room creates room and room_connected is true" do
      {:ok, pid} = AgentSession.start_link(real_config())

      assert :ok = AgentSession.connect_to_room(pid)
      status = AgentSession.get_status(pid)
      assert status.room_connected == true

      AgentSession.disconnect_from_room(pid)
      GenServer.stop(pid)
    end

    test "disconnect_from_room sets room_connected to false" do
      {:ok, pid} = AgentSession.start_link(real_config())

      AgentSession.connect_to_room(pid)
      assert AgentSession.get_status(pid).room_connected == true

      AgentSession.disconnect_from_room(pid)
      assert AgentSession.get_status(pid).room_connected == false

      GenServer.stop(pid)
    end

    test "connect_to_room fails when pipeline_config is nil" do
      config = real_config() |> Map.put(:pipeline_config, nil)
      {:ok, pid} = AgentSession.start_link(config)

      assert {:error, :missing_pipeline_config} = AgentSession.connect_to_room(pid)

      GenServer.stop(pid)
    end

    test "terminate cleans up children without crash" do
      {:ok, pid} = AgentSession.start_link(real_config())
      AgentSession.connect_to_room(pid)

      ref = Process.monitor(pid)
      GenServer.stop(pid, :normal, 5_000)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
    end
  end
end

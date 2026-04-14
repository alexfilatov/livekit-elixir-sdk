defmodule Livekit.Agents.VADTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.VAD.VADEvent
  alias Livekit.Agents.AudioFrame

  defmodule StubVAD do
    use Livekit.Agents.VAD

    @impl true
    def stream(_config) do
      pid = spawn(fn -> receive do :stop -> :ok end end)
      {:ok, pid}
    end

    @impl true
    def capabilities do
      %{realtime: true, speech_probability: false}
    end
  end

  test "StubVAD.stream/1 returns {:ok, pid}" do
    assert {:ok, pid} = StubVAD.stream(%{})
    assert is_pid(pid)
    send(pid, :stop)
  end

  test "capabilities/0 returns map with all required VAD keys" do
    caps = StubVAD.capabilities()
    assert Map.has_key?(caps, :realtime)
    assert Map.has_key?(caps, :speech_probability)
  end

  test "capabilities realtime is boolean" do
    caps = StubVAD.capabilities()
    assert is_boolean(caps.realtime)
  end

  test "default validate_config/1 returns :ok" do
    assert :ok == StubVAD.validate_config(%{})
  end

  test "VADEvent struct has correct defaults" do
    event = %VADEvent{}
    assert event.type == nil
    assert event.probability == 0.0
    assert event.frames == []
  end

  test "VADEvent struct accepts all valid type atoms" do
    assert %VADEvent{type: :speech_start}
    assert %VADEvent{type: :speech_end}
    assert %VADEvent{type: :inference}
  end

  test "VADEvent frames field accepts a list of AudioFrame structs" do
    frame = %AudioFrame{}
    event = %VADEvent{type: :speech_end, frames: [frame]}
    assert length(event.frames) == 1
  end
end

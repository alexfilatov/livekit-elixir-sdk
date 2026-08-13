defmodule Livekit.Agents.STT.DeepgramStreamTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.STT.Deepgram
  alias Livekit.Agents.STT.Deepgram.Config
  alias Livekit.Agents.STT.DeepgramStream

  describe "start_link/1 with api_key" do
    test "returns {:ok, pid} when api_key is provided" do
      config = %Config{api_key: "dg_test_key"}
      # The GenServer starts and immediately tries to connect — the connection
      # will fail since there is no real server, but init itself succeeds.
      assert {:ok, pid} = DeepgramStream.start_link({config, self()})
      assert is_pid(pid)
      # Clean up — the process may exit after failing to connect; that is fine.
      Process.sleep(20)
    end
  end

  describe "send_audio/2" do
    test "discards audio when finishing is true (no crash)" do
      # We can exercise the finishing path by sending :finish before audio.
      config = %Config{api_key: "dg_test_key"}
      {:ok, pid} = DeepgramStream.start_link({config, self()})
      # finish sets finishing: true; subsequent send_audio must not crash.
      DeepgramStream.finish(pid)
      DeepgramStream.send_audio(pid, <<0, 1, 2, 3>>)
      # If we reach here without an exception, the test passes.
      assert true
    end
  end

  describe "Deepgram.stream/1" do
    test "returns {:ok, pid} with a valid api_key" do
      config = %Config{api_key: "dg_test_key"}
      assert {:ok, pid} = Deepgram.stream(config)
      assert is_pid(pid)
      Process.sleep(20)
    end
  end
end

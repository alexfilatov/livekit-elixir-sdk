defmodule Livekit.Agents.AgentSessionURLTest do
  use ExUnit.Case, async: true

  @moduledoc """
  The URL a dispatched session hands to the WebRTC client.

  LiveKit Cloud puts an `https://` regional URL in the job assignment, and the
  Rust client only accepts ws/wss. Given https it fails with "failed to
  retrieve region info: error sending request for url (...)" — naming an
  address that is reachable, over a network that works, which sends you
  looking at DNS and firewalls for an hour.
  """

  alias Livekit.Agents.AgentSession

  defmodule RecordingNIF do
    # room_connect runs inside the Room GenServer, so a bare `self()` here
    # would report to a process the test cannot see.
    def room_connect(url, _token, _pid) do
      send(Application.fetch_env!(:livekit, :test_reporter), {:room_connect, url})
      {:error, :not_connecting_in_a_test}
    end
  end

  setup do
    Application.put_env(:livekit, :test_reporter, self())
    on_exit(fn -> Application.delete_env(:livekit, :test_reporter) end)
    :ok
  end

  defp url_used(server_url) do
    config = %AgentSession.Config{
      room_name: "r",
      server_url: server_url,
      api_key: "k",
      api_secret: "secret-at-least-32-bytes-long-ok!!",
      pipeline_config: nil,
      nif_module: RecordingNIF
    }

    {:ok, pid} = AgentSession.start_link(config)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    AgentSession.connect_to_room(pid)
  end

  test "an https assignment URL is converted to wss" do
    url_used("https://project.region.production.livekit.cloud")
    assert_receive {:room_connect, "wss://project.region.production.livekit.cloud"}, 2000
  end

  test "an http assignment URL is converted to ws" do
    url_used("http://localhost:7880")
    assert_receive {:room_connect, "ws://localhost:7880"}, 2000
  end

  test "a wss URL is left alone" do
    url_used("wss://project.livekit.cloud")
    assert_receive {:room_connect, "wss://project.livekit.cloud"}, 2000
  end
end

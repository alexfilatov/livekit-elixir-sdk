defmodule Livekit.Agents.WorkerAuthTest do
  use ExUnit.Case, async: true

  @moduledoc """
  The token a worker registers with.

  LiveKit's agent worker endpoint requires the `agent` grant. Without it the
  WebSocket upgrade is refused with a 401 — and gun reports a refused upgrade
  as `{:gun_response, ...}`, which is not `{:gun_upgrade, ...}`, so a worker
  that does not handle it sits there having logged "Starting" and nothing
  else. That is exactly how this shipped: silent, healthy-looking, and never
  dispatched a single job.
  """

  alias Livekit.{AccessToken, Grants, TokenVerifier}

  test "the agent grant exists and reaches the JWT" do
    jwt =
      "key"
      |> AccessToken.new("secret-at-least-32-bytes-long-ok!!")
      |> AccessToken.with_identity("worker-1")
      |> AccessToken.with_grants(%Grants{agent: true})
      |> AccessToken.to_jwt()

    {:ok, claims} = TokenVerifier.verify(jwt, "secret-at-least-32-bytes-long-ok!!")

    assert get_in(claims, ["video", "agent"]) == true
  end

  test "a refused upgrade is reported and retried, not swallowed" do
    {:ok, pid} =
      Livekit.Agents.Worker.start_link(%Livekit.Agents.Worker.Config{
        server_url: "mock://test",
        api_key: "k",
        api_secret: "s",
        entrypoint: fn _ -> :ok end
      })

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    # Exactly what gun sends when the server rejects the upgrade.
    send(pid, {:gun_response, nil, nil, :fin, 401, []})

    state = :sys.get_state(pid)

    # Previously this fell through to the catch-all and vanished. The
    # connection must be torn down and retried, not left half-open forever.
    assert state.registered == false
    assert state.gun_pid == nil
    assert Process.alive?(pid)
  end

  test "a worker's registration token carries it" do
    config = %Livekit.Agents.Worker.Config{
      api_key: "key",
      api_secret: "secret-at-least-32-bytes-long-ok!!",
      worker_id: "worker-1",
      entrypoint: fn _ -> :ok end
    }

    jwt = Livekit.Agents.Worker.registration_token(config)
    {:ok, claims} = TokenVerifier.verify(jwt, config.api_secret)

    # Without this the upgrade is refused and nothing in the SDK says so.
    assert get_in(claims, ["video", "agent"]) == true
    assert claims["sub"] == "worker-1"
  end
end

defmodule Livekit.Agents.WorkerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Livekit.Agents.Worker

  defp start_worker(overrides \\ []) do
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

  # ---------------------------------------------------------------------------
  # Registration (mock mode)
  # ---------------------------------------------------------------------------

  describe "mock mode registration" do
    test "starts and registers in mock mode" do
      pid = start_worker()
      Process.sleep(50)
      status = Worker.get_status(pid)
      assert status.registered == true
    end

    test "generates worker_id when nil" do
      pid = start_worker(worker_id: nil)
      Process.sleep(50)
      status = Worker.get_status(pid)
      assert status.worker_id =~ ~r/^elixir-worker-/
    end

    test "preserves supplied worker_id" do
      pid = start_worker(worker_id: "my-worker")
      Process.sleep(50)
      status = Worker.get_status(pid)
      assert status.worker_id == "my-worker"
    end
  end

  # ---------------------------------------------------------------------------
  # Heartbeat
  # ---------------------------------------------------------------------------

  describe "heartbeat" do
    test "updates last_heartbeat when triggered" do
      pid = start_worker()
      Process.sleep(50)
      status1 = Worker.get_status(pid)

      send(pid, :heartbeat)
      Process.sleep(50)

      status2 = Worker.get_status(pid)
      assert status2.last_heartbeat != nil

      # If last_heartbeat was already set, it should be >= the previous value
      if status1.last_heartbeat != nil do
        assert DateTime.compare(status2.last_heartbeat, status1.last_heartbeat) in [:gt, :eq]
      end
    end

    test "load reflects active job ratio at 0 initially" do
      pid = start_worker(max_concurrent_jobs: 4)
      Process.sleep(50)
      status = Worker.get_status(pid)
      assert status.load == 0.0
    end
  end

  # ---------------------------------------------------------------------------
  # Capacity enforcement
  # ---------------------------------------------------------------------------

  describe "capacity" do
    test "active_jobs count reflects injected state" do
      pid = start_worker(max_concurrent_jobs: 1)
      Process.sleep(50)

      :sys.replace_state(pid, fn state ->
        fake_jobs = %{
          "fake-job" => %{
            session_pid: self(),
            monitor_ref: make_ref(),
            room_name: "test-room",
            participant_identity: "user-1",
            started_at: DateTime.utc_now()
          }
        }

        %{state | active_jobs: fake_jobs}
      end)

      status = Worker.get_status(pid)
      assert status.active_jobs == 1
      assert status.load == 1.0
    end
  end

  # ---------------------------------------------------------------------------
  # Drain
  # ---------------------------------------------------------------------------

  describe "drain" do
    test "returns :ok immediately with no active jobs" do
      pid = start_worker()
      Process.sleep(50)

      # drain stops the worker after :ok, so on_exit cleanup is a no-op
      result = Worker.drain(pid)
      assert result == :ok
    end

    test "waits for in-flight job then returns :ok" do
      pid = start_worker()
      Process.sleep(50)

      session = spawn(fn -> Process.sleep(500) end)

      # :sys.replace_state callback runs in the Worker GenServer process,
      # so Process.monitor/1 here creates a monitor owned by the Worker.
      :sys.replace_state(pid, fn state ->
        # Monitor created from within the Worker process context
        ref = Process.monitor(session)

        jobs = %{
          "job-1" => %{
            session_pid: session,
            monitor_ref: ref,
            room_name: "drain-room",
            participant_identity: "user-1",
            started_at: DateTime.utc_now()
          }
        }

        %{state | active_jobs: jobs, draining: false}
      end)

      task = Task.async(fn -> Worker.drain(pid) end)
      Process.exit(session, :normal)

      assert Task.await(task, 2_000) == :ok
    end

    test "returns {:error, :timeout} when jobs take too long" do
      pid = start_worker(drain_timeout: 200)
      Process.sleep(50)

      long_session = spawn(fn -> Process.sleep(10_000) end)

      # Monitor created from within the Worker process context
      :sys.replace_state(pid, fn state ->
        ref = Process.monitor(long_session)

        jobs = %{
          "job-timeout" => %{
            session_pid: long_session,
            monitor_ref: ref,
            room_name: "slow-room",
            participant_identity: "user-1",
            started_at: DateTime.utc_now()
          }
        }

        %{state | active_jobs: jobs, draining: false}
      end)

      # drain_timeout is 200ms; call timeout is 90s by default
      result = Worker.drain(pid)
      Process.exit(long_session, :kill)

      assert result == {:error, :timeout}
    end
  end

  # ---------------------------------------------------------------------------
  # get_status fields
  # ---------------------------------------------------------------------------

  describe "get_status" do
    test "returns required fields" do
      pid = start_worker()
      Process.sleep(50)
      status = Worker.get_status(pid)

      present_keys = Map.keys(status)

      for key <- [:worker_id, :registered, :active_jobs, :max_concurrent_jobs, :draining, :load] do
        assert key in present_keys, "Missing key: #{key}"
      end

      assert Map.has_key?(status, :last_heartbeat)
    end

    test "active_jobs count is non-negative integer" do
      pid = start_worker()
      Process.sleep(50)
      status = Worker.get_status(pid)
      assert is_integer(status.active_jobs)
      assert status.active_jobs >= 0
    end

    test "draining is false initially" do
      pid = start_worker()
      Process.sleep(50)
      status = Worker.get_status(pid)
      assert status.draining == false
    end
  end
end

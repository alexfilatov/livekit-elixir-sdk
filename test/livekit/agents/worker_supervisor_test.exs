defmodule Livekit.Agents.WorkerSupervisorTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Livekit.Agents.{JobSupervisor, Worker, WorkerSupervisor}

  # WorkerSupervisor registers itself under its module name globally, so we
  # must stop any running instance before each test to avoid conflicts.
  setup do
    if pid = Process.whereis(WorkerSupervisor) do
      Supervisor.stop(pid, :normal, 2_000)
    end

    :ok
  end

  # Safely stop a supervisor, ignoring errors if it is already dead.
  defp stop_supervisor(pid) do
    try do
      if Process.alive?(pid), do: Supervisor.stop(pid, :normal, 2_000)
    catch
      :exit, _ -> :ok
    end
  end

  defp test_config do
    %Worker.Config{
      api_key: "test-key",
      api_secret: "test-secret",
      entrypoint: fn _ctx -> :ok end,
      server_url: nil,
      max_concurrent_jobs: 5,
      heartbeat_interval: 60_000
    }
  end

  describe "start_link/1" do
    test "starts the supervision tree" do
      {:ok, sup_pid} = WorkerSupervisor.start_link(test_config())
      on_exit(fn -> stop_supervisor(sup_pid) end)
      assert Process.alive?(sup_pid)
    end

    test "Worker and JobSupervisor are children" do
      {:ok, sup_pid} = WorkerSupervisor.start_link(test_config())
      on_exit(fn -> stop_supervisor(sup_pid) end)

      children = Supervisor.which_children(sup_pid)
      assert length(children) == 2

      child_ids = Enum.map(children, fn {id, _pid, _type, _modules} -> id end)
      assert JobSupervisor in child_ids
      assert Worker in child_ids
    end

    test "Worker child restarts if killed" do
      {:ok, sup_pid} = WorkerSupervisor.start_link(test_config())
      on_exit(fn -> stop_supervisor(sup_pid) end)

      children = Supervisor.which_children(sup_pid)

      {Worker, worker_pid, _type, _modules} =
        Enum.find(children, fn {id, _, _, _} -> id == Worker end)

      Process.exit(worker_pid, :kill)
      Process.sleep(200)

      new_children = Supervisor.which_children(sup_pid)

      {Worker, new_worker_pid, _type, _modules} =
        Enum.find(new_children, fn {id, _, _, _} -> id == Worker end)

      assert is_pid(new_worker_pid)
      assert Process.alive?(new_worker_pid)
      assert new_worker_pid != worker_pid
    end

    test "JobSupervisor child restarts if killed" do
      {:ok, sup_pid} = WorkerSupervisor.start_link(test_config())
      on_exit(fn -> stop_supervisor(sup_pid) end)

      children = Supervisor.which_children(sup_pid)

      {JobSupervisor, job_sup_pid, _type, _modules} =
        Enum.find(children, fn {id, _, _, _} -> id == JobSupervisor end)

      Process.exit(job_sup_pid, :kill)
      Process.sleep(200)

      new_children = Supervisor.which_children(sup_pid)

      {JobSupervisor, new_job_sup_pid, _type, _modules} =
        Enum.find(new_children, fn {id, _, _, _} -> id == JobSupervisor end)

      assert is_pid(new_job_sup_pid)
      assert Process.alive?(new_job_sup_pid)
      assert new_job_sup_pid != job_sup_pid
    end
  end
end

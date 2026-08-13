defmodule Livekit.Agents.WorkerDispatchTest do
  # Not async: the worker starts sessions under the global JobSupervisor.
  use ExUnit.Case, async: false

  @moduledoc """
  What happens when LiveKit actually dispatches a job to this worker.

  `entrypoint` was required config, documented as "function called with a
  JobContext to run the agent" — and never called. The worker started every
  assigned session with `pipeline_config: nil`, which `AgentSession` documents
  as required for real mode, so a dispatched agent joined the room deaf and
  mute. Nothing failed; the agent was simply silent, which is the worst way
  for this to break.
  """

  alias Livekit.Agents.{Pipeline, Worker}
  alias Livekit.{Job, JobAssignment, Room, ServerMessage}

  setup do
    # The SDK ships no supervision tree, so nothing starts JobSupervisor —
    # a host application running a worker must start it or every assigned job
    # dies on `:noproc`. See the accessory's Application module.
    start_supervised!({Livekit.Agents.JobSupervisor, name: Livekit.Agents.JobSupervisor})
    :ok
  end

  defp start_worker(entrypoint) do
    {:ok, pid} =
      Worker.start_link(%Worker.Config{
        # mock mode: no Gun, no server, but the assignment path is the real one
        server_url: "mock://test",
        api_key: "k",
        api_secret: "s",
        entrypoint: entrypoint
      })

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    pid
  end

  # Exactly the frame Gun hands the worker when the server assigns a job.
  defp assign(pid, room_name) do
    frame =
      ServerMessage.encode(%ServerMessage{
        message:
          {:assignment,
           %JobAssignment{
             job: %Job{id: "job-1", room: %Room{name: room_name}},
             url: nil
           }}
      })

    send(pid, {:gun_ws, nil, nil, {:binary, frame}})
    # Let the worker process the frame before asserting.
    _ = :sys.get_state(pid)
  end

  test "the entrypoint is called with the room it was dispatched into" do
    test_pid = self()

    pid =
      start_worker(fn ctx ->
        send(test_pid, {:entrypoint_called, ctx})
        :ok
      end)

    assign(pid, "board-42")

    assert_receive {:entrypoint_called, ctx}, 1000

    # The room name is the only thing that tells the agent which property it
    # is standing outside. Without it the entrypoint cannot choose a prompt.
    assert ctx.room_name == "board-42"
    assert ctx.job_id == "job-1"
  end

  test "the pipeline the entrypoint returns reaches the session" do
    config = %Pipeline.Config{llm_opts: [instructions: "You are a UK estate agent."]}

    pid = start_worker(fn _ctx -> {:ok, config} end)
    assign(pid, "board-7")

    [{_id, job}] = Map.to_list(:sys.get_state(pid).active_jobs)
    session_config = :sys.get_state(job.session_pid).config

    # The whole point: a session that carries the instructions for THIS room.
    assert session_config.pipeline_config == config
  end

  test "a room job with no participant still gets an identity" do
    pid = start_worker(fn _ctx -> :ok end)
    assign(pid, "board-42")

    [{_id, job}] = Map.to_list(:sys.get_state(pid).active_jobs)

    # A room-type job names no participant. An empty identity produces a join
    # token with an empty `sub`, which LiveKit refuses as
    # "401 Unauthorized - missing authorization header" — a message that
    # blames the header rather than what is missing inside it.
    assert job.participant_identity == "agent-job-1"
    assert job.participant_identity != ""
  end

  test "an entrypoint that declines the job means no session starts" do
    pid = start_worker(fn _ctx -> {:error, :out_of_credit} end)
    assign(pid, "board-7")

    state = :sys.get_state(pid)
    assert state.active_jobs == %{}
    assert state.metrics.jobs_failed == 1
  end

  test "an entrypoint that raises loses one job, not the worker" do
    pid = start_worker(fn _ctx -> raise "boom" end)
    assign(pid, "board-7")

    # A bad prompt lookup for one visitor must not hang up on everyone else
    # already mid-conversation.
    assert Process.alive?(pid)
    assert :sys.get_state(pid).active_jobs == %{}
  end
end

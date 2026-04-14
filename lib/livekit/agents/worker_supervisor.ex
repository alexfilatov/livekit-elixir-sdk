defmodule Livekit.Agents.WorkerSupervisor do
  @moduledoc """
  Top-level supervisor for the LiveKit agent worker infrastructure.

  Starts and supervises:
  1. `Livekit.Agents.JobSupervisor` — a DynamicSupervisor that manages one
     `AgentSession` child per assigned job.
  2. `Livekit.Agents.Worker` — the GenServer that maintains the WebSocket
     connection to the LiveKit server, handles job dispatch, and sends
     periodic heartbeats.

  The `JobSupervisor` is listed first so it is fully started before the
  `Worker` begins connecting and accepting jobs.

  ## Usage

      {:ok, _pid} = WorkerSupervisor.start_link(%Worker.Config{
        api_key: "my-key",
        api_secret: "my-secret",
        entrypoint: &MyAgent.run/1
      })
  """

  use Supervisor

  alias Livekit.Agents.{JobSupervisor, Worker}

  @doc """
  Starts the WorkerSupervisor and its children.

  Accepts a `Worker.Config` struct. The supervisor is registered locally as
  `#{__MODULE__}` so only one instance runs per node by default.
  """
  @spec start_link(Worker.Config.t()) :: Supervisor.on_start()
  def start_link(worker_config) do
    Supervisor.start_link(__MODULE__, worker_config, name: __MODULE__)
  end

  @impl true
  def init(worker_config) do
    children = [
      {JobSupervisor, [name: JobSupervisor]},
      {Worker, {worker_config, [name: Worker]}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

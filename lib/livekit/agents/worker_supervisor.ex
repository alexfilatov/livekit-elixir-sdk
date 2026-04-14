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

  Accepts a `Worker.Config` struct and an optional keyword list of options.

  ## Options

  - `:name` — registration name for the supervisor (default: `#{__MODULE__}`).
  - `:worker_name` — registration name for the `Worker` child
    (default: derived from `worker_config.worker_id` when present, else `Worker`).
  """
  @spec start_link(Worker.Config.t(), keyword()) :: Supervisor.on_start()
  def start_link(worker_config, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, {worker_config, opts}, name: name)
  end

  @impl true
  def init({worker_config, opts}) do
    worker_name =
      Keyword.get_lazy(opts, :worker_name, fn ->
        if Map.get(worker_config, :worker_id) do
          {:via, Registry, {Livekit.Agents.WorkerRegistry, worker_config.worker_id}}
        else
          Worker
        end
      end)

    children = [
      {JobSupervisor, [name: JobSupervisor]},
      {Worker, {worker_config, [name: worker_name]}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

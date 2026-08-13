defmodule Livekit.Agents.JobSupervisor do
  @moduledoc """
  DynamicSupervisor that manages one `AgentSession` child per assigned job.

  Started by `WorkerSupervisor` before the `Worker` so it is ready to accept
  children the moment the Worker receives a job assignment.

  ## Usage

      # Start a new job session
      {:ok, pid} = JobSupervisor.start_job(session_config)

      # Query active job count
      count = JobSupervisor.active_jobs()
  """

  use DynamicSupervisor

  alias Livekit.Agents.AgentSession

  @doc """
  Starts the JobSupervisor.

  Accepts a keyword list that must include a `name:` key so the supervisor
  can be referenced by name from `Worker`.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    DynamicSupervisor.start_link(__MODULE__, :ok, name: name)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new `AgentSession` child under the given supervisor.

  ## Parameters

  - `supervisor` — the supervisor name or pid (defaults to `#{__MODULE__}`)
  - `session_config` — an `AgentSession.Config` struct describing the job

  ## Returns

  `{:ok, pid}` on success, or `{:error, reason}` on failure.
  """
  @spec start_job(supervisor :: pid() | atom(), session_config :: AgentSession.Config.t()) ::
          DynamicSupervisor.on_start_child()
  def start_job(supervisor \\ __MODULE__, session_config) do
    child_spec = {AgentSession, session_config}
    DynamicSupervisor.start_child(supervisor, child_spec)
  end

  @doc """
  Returns the number of currently active job sessions supervised by
  the given supervisor.

  ## Parameters

  - `supervisor` — the supervisor name or pid (defaults to `#{__MODULE__}`)
  """
  @spec active_jobs(supervisor :: pid() | atom()) :: non_neg_integer()
  def active_jobs(supervisor \\ __MODULE__) do
    DynamicSupervisor.which_children(supervisor) |> length()
  end
end

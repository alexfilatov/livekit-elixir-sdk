---
phase: 09-worker-infrastructure
plan: "02"
subsystem: testing
tags: [worker, supervisor, job-supervisor, mock-mode, drain, exunit]
dependency_graph:
  requires: [09-01]
  provides: [TEST-06]
  affects: []
tech_stack:
  added: []
  patterns:
    - ":sys.replace_state/2 for injecting fake GenServer state in tests (Worker process context)"
    - "DynamicSupervisor.terminate_child/2 for safe child removal without triggering restart"
    - "try/catch :exit in on_exit callbacks for supervisor cleanup resilience"
key_files:
  created:
    - test/livekit/agents/worker_supervisor_test.exs
    - test/livekit/agents/job_supervisor_test.exs
    - test/livekit/agents/worker_test.exs
  modified: []
decisions:
  - "Used DynamicSupervisor.terminate_child/2 instead of GenServer.stop to decrement active_jobs — AgentSession child_spec defaults to restart: :permanent, so GenServer.stop(:normal) triggers a restart and count stays at 1"
  - "Used :sys.replace_state inside Worker process context so Process.monitor/1 creates refs owned by the Worker, not the test process — required for DOWN message routing in drain tests"
  - "Used dummy server_url (http://localhost:7880) in AgentSession configs — RoomServiceClient.new/3 calls String.replace on nil which crashes; AgentSession mock-connects without making real HTTP calls"
  - "Wrapped on_exit supervisor cleanup in try/catch :exit — supervisors can die between test end and on_exit execution when child restart intensity is exhausted"
  - "WorkerSupervisor tests use async: false (globally named supervisor); JobSupervisor tests use async: true with unique per-test names via :erlang.unique_integer"
metrics:
  duration_minutes: 7
  tasks_completed: 2
  files_created: 3
  completed_date: "2026-04-14"
---

# Phase 9 Plan 02: Worker Infrastructure Tests Summary

ExUnit test suite for all Phase 9 worker infrastructure modules — 20 tests covering WorkerSupervisor supervision tree, JobSupervisor dynamic child management, and Worker GenServer mock mode with heartbeat, capacity enforcement, drain, and status reporting.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | WorkerSupervisor and JobSupervisor tests | 2338a59 | worker_supervisor_test.exs, job_supervisor_test.exs |
| 2 | Worker GenServer tests (mock mode, heartbeat, capacity, drain) | a1d8858 | worker_test.exs |

## Test Coverage

### WorkerSupervisor (4 tests, async: false)
- `start_link/1` starts supervision tree and returns alive pid
- Worker and JobSupervisor are both children (verified by id)
- Worker child restarts when killed (new pid, same supervisor)
- JobSupervisor child restarts when killed (new pid, same supervisor)

### JobSupervisor (4 tests, async: true)
- `active_jobs/1` returns 0 on fresh supervisor
- `start_job/2` starts AgentSession child and increments count to 1
- Active jobs decrements to 0 after `DynamicSupervisor.terminate_child/2`
- Three concurrent jobs tracked correctly (active_jobs == 3)

### Worker (12 tests, async: true)
- Mock mode registration: `registered == true` after init
- Worker ID auto-generation matches `~r/^elixir-worker-/`
- Supplied worker_id is preserved
- Heartbeat sets `last_heartbeat` field
- Initial load is `0.0` with no active jobs
- Capacity: `active_jobs` count correct after `:sys.replace_state` injection
- Drain with no jobs returns `:ok` immediately
- Drain waits for in-flight job (injected via `:sys.replace_state`) then returns `:ok`
- Drain returns `{:error, :timeout}` when drain_timeout exceeded
- `get_status/1` returns all required fields: worker_id, registered, active_jobs, max_concurrent_jobs, draining, load, last_heartbeat

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] AgentSession crashes with nil server_url**
- **Found during:** Task 1 (JobSupervisor start_job tests)
- **Issue:** `RoomServiceClient.new(nil, api_key, api_secret)` calls `String.replace(nil, ...)` which raises `FunctionClauseError`, causing `AgentSession.init` to crash and `start_job` to return `{:error, _}`
- **Fix:** Changed `session_config` helper in `job_supervisor_test.exs` to use `server_url: "http://localhost:7880"` — AgentSession mock-connects without making real HTTP calls
- **Files modified:** test/livekit/agents/job_supervisor_test.exs

**2. [Rule 1 - Bug] :sys.replace_state monitor ref owned by wrong process**
- **Found during:** Task 2 (drain tests)
- **Issue:** Plan showed `Process.monitor(session)` in the test process before injecting into Worker state. The resulting ref is owned by the test process, so the Worker's `handle_info({:DOWN, ...})` never matches it — drain blocks forever
- **Fix:** Moved `Process.monitor(session)` inside the `:sys.replace_state` callback, which runs in the Worker process context, creating a Worker-owned monitor ref
- **Files modified:** test/livekit/agents/worker_test.exs

**3. [Rule 2 - Missing critical functionality] DynamicSupervisor child restart interference**
- **Found during:** Task 1 (active_jobs decrement test)
- **Issue:** `AgentSession` child_spec defaults to `restart: :permanent`. `GenServer.stop(session_pid)` triggers a restart, keeping `active_jobs` at 1 — the assertion `== 0` always fails
- **Fix:** Used `DynamicSupervisor.terminate_child(sup, session_pid)` which removes the child from the supervisor without restarting it regardless of restart strategy
- **Files modified:** test/livekit/agents/job_supervisor_test.exs

**4. [Rule 2 - Missing critical functionality] on_exit supervisor cleanup races**
- **Found during:** Tasks 1 and 2
- **Issue:** Supervisors can die between test completion and `on_exit` execution (restart intensity exhaustion from the `spawn_link` in AgentSession). `Supervisor.stop` raises `:exit` on a dead pid
- **Fix:** Wrapped all supervisor `on_exit` callbacks in `try/catch :exit` blocks; added `stop_supervisor/1` helper in WorkerSupervisor tests
- **Files modified:** test/livekit/agents/worker_supervisor_test.exs, test/livekit/agents/job_supervisor_test.exs

**5. [Rule 1 - Bug] ExUnit.skip/1 does not exist**
- **Found during:** Task 1 compilation
- **Issue:** Plan specified `ExUnit.skip("reason")` as fallback for AgentSession failures, but this function does not exist in ExUnit 1.18
- **Fix:** Replaced with `raise ExUnit.SkipError, "reason"` (the correct runtime skip mechanism). After fix #1 these skip paths are no longer hit in practice
- **Files modified:** test/livekit/agents/job_supervisor_test.exs

## Known Stubs

None. All tests exercise real module behavior.

## Self-Check: PASSED

- test/livekit/agents/worker_supervisor_test.exs — EXISTS
- test/livekit/agents/job_supervisor_test.exs — EXISTS
- test/livekit/agents/worker_test.exs — EXISTS
- Commit 2338a59 — EXISTS (test(09-02): add WorkerSupervisor and JobSupervisor tests)
- Commit a1d8858 — EXISTS (test(09-02): add Worker GenServer tests)
- Final test run: 20 tests, 0 failures

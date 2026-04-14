---
phase: 09-worker-infrastructure
plan: "01"
subsystem: agents-worker
tags: [otp, supervision, websocket, gun, heartbeat, drain]
dependency_graph:
  requires: []
  provides: [WorkerSupervisor, JobSupervisor, Worker-Gun-WebSocket]
  affects: [lib/mix/tasks/livekit.agents.start.ex, lib/mix/tasks/livekit.agents.dev.ex]
tech_stack:
  added: []
  patterns: [one_for_one supervision, DynamicSupervisor, Gun WebSocket, exponential backoff, deferred GenServer reply for drain]
key_files:
  created:
    - lib/livekit/agents/worker_supervisor.ex
    - lib/livekit/agents/job_supervisor.ex
  modified:
    - lib/livekit/agents/worker.ex
    - lib/mix/tasks/livekit.agents.start.ex
    - lib/mix/tasks/livekit.agents.dev.ex
decisions:
  - "JSON text frames over WebSocket (not binary protobuf) for now, enabling mock inspection without a full protobuf dependency"
  - "Worker.start_link/2 accepts both {config, opts} tuple and (config, opts) arities to support Supervisor child_spec"
  - "drain/1 uses deferred GenServer reply pattern (handle_call returns :noreply, reply sent from DOWN handler)"
  - "register_worker/1 public API removed; registration is now automatic on WebSocket upgrade"
metrics:
  duration_minutes: 3
  completed_date: "2026-04-14"
  tasks_completed: 2
  files_modified: 5
---

# Phase 9 Plan 01: Worker Infrastructure — Supervision Tree + Worker Refactor Summary

**One-liner:** OTP supervision tree (WorkerSupervisor -> JobSupervisor + Worker) with Gun WebSocket connection, heartbeat load reporting, job dispatch with capacity enforcement, and graceful drain.

## What Was Built

### WorkerSupervisor (`lib/livekit/agents/worker_supervisor.ex`)
Top-level `one_for_one` Supervisor. Children are listed in start order: JobSupervisor first (so it is ready to accept children before Worker connects), then Worker. Registered as `{:local, __MODULE__}` for single-node deployments.

### JobSupervisor (`lib/livekit/agents/job_supervisor.ex`)
`DynamicSupervisor` with two public functions:
- `start_job/2` — starts an `AgentSession` child for a newly assigned job
- `active_jobs/1` — returns the count of currently supervised sessions

### Worker (`lib/livekit/agents/worker.ex`)
Complete rewrite of the mock GenServer:

**Connection flow:** `:connect` -> `:gun.open` -> `gun_up` -> `ws_upgrade` -> `gun_upgrade` -> send register JSON -> schedule heartbeat

**Heartbeat:** Every `heartbeat_interval` ms, sends `{type: "keepalive", load: active/max}`. Suppressed when draining with no active jobs.

**Job lifecycle:**
- `availability_request` — accepts if not draining and under capacity (T-09-03)
- `job_assignment` — validates room_name and participant_identity are non-empty strings (T-09-02), spawns `AgentSession` under `JobSupervisor`, monitors the pid
- Session `DOWN` — removes from `active_jobs`; if draining and empty, replies drain caller and stops

**Drain:** `handle_call(:drain)` sets `draining: true`, sends deregister, defers reply via `:noreply` until all sessions finish or `drain_timeout` expires.

**Mock mode:** When `server_url` is nil or starts with `"mock://"`, all Gun calls are skipped and heartbeats are logged. Safe for testing.

**Reconnect:** Exponential backoff (1s -> 2s -> 4s... capped at 30s) on `gun_down` or Gun process `DOWN`.

## Commits

| Hash | Message |
|------|---------|
| `1e786b8` | feat(09-01): add WorkerSupervisor and JobSupervisor |
| `a0fb5b6` | feat(09-01): refactor Worker with Gun WebSocket, heartbeat, drain, load |
| `4fd7071` | fix(09-01): remove dead register_worker calls from Mix tasks |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed dead `register_worker/1` calls in Mix tasks**
- **Found during:** Task 2 verification (`mix compile` warning)
- **Issue:** `Worker.register_worker/1` was removed from the public API (registration now automatic on WebSocket upgrade), but `Mix.Tasks.Livekit.Agents.Start` and `Mix.Tasks.Livekit.Agents.Dev` still called it
- **Fix:** Removed the `register_workers/1` private helper and its call in `livekit.agents.start.ex`; replaced the call in `livekit.agents.dev.ex` with an info log
- **Files modified:** `lib/mix/tasks/livekit.agents.start.ex`, `lib/mix/tasks/livekit.agents.dev.ex`
- **Commit:** `4fd7071`

## Threat Mitigations Implemented

| ID | Mitigation |
|----|-----------|
| T-09-02 | `require_string_field/2` validates `room_name` and `participant_identity` are non-empty binary strings; malformed payloads are rejected with `Logger.warning` |
| T-09-03 | `handle_availability_request/2` enforces `max_concurrent_jobs` cap before accepting any job |
| T-09-04 | `api_secret` is never logged; only `worker_id`, job IDs, and room names appear in log messages |

## Known Stubs

None — all data flows are wired. The Worker sends real Gun frames and dispatches real `AgentSession` children. `AgentSession` itself still has a mock room-connection stub, but that is a pre-existing condition outside this plan's scope.

## Self-Check: PASSED

- `lib/livekit/agents/worker_supervisor.ex` — exists, confirmed created
- `lib/livekit/agents/job_supervisor.ex` — exists, confirmed created
- `lib/livekit/agents/worker.ex` — exists, refactored
- Commits `1e786b8`, `a0fb5b6`, `4fd7071` — all present in `git log`
- `mix compile` — no errors
- `mix credo --strict` on all three new/modified agent files — 0 issues

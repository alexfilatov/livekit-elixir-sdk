---
phase: 13
plan: "01"
subsystem: worker-protocol
tags: [protobuf, websocket, worker, livekit-protocol]
dependency_graph:
  requires: [worker.ex, livekit_models.proto, protobuf library]
  provides: [livekit_agent.proto, livekit_agent.pb.ex, worker protobuf protocol]
  affects: [Worker GenServer wire format, WorkerSupervisor, JobSupervisor]
tech_stack:
  added: [livekit_agent.proto proto definitions, livekit/proto/livekit_agent.pb.ex]
  patterns: [protobuf binary WebSocket frames, oneof message dispatch, enum atom/int duality]
key_files:
  created:
    - proto/livekit_agent.proto
    - lib/livekit/proto/livekit_agent.pb.ex
    - test/livekit/agents/worker_protocol_test.exs
  modified:
    - lib/livekit/agents/worker.ex
    - proto/livekit_models.proto
    - lib/livekit/proto/livekit_models.pb.ex
decisions:
  - Used protoc + protoc-gen-elixir to generate pb.ex rather than handwriting it
  - Added ServerInfo to livekit_models.proto (missing from local copy vs upstream)
  - Auth JWT added to WebSocket upgrade headers using existing Livekit.Grants
  - Enum decoded fields are atoms in Elixir protobuf library (not integers)
  - struct! cannot set oneof fields; use %WorkerMessage{message: {field, payload}}
metrics:
  duration: "~45 minutes"
  completed: "2026-04-14"
  tasks: 4
  files: 6
---

# Phase 13 Plan 01: Real Worker-Server Protocol (Protobuf) Summary

Replaced the Worker's JSON WebSocket messages with real LiveKit protobuf binary frames,
matching the Python agents framework wire protocol exactly.

## What Was Built

### Proto Definitions

`proto/livekit_agent.proto` — full LiveKit agent worker protocol:

- **`WorkerMessage`** (worker → server): oneof with `RegisterWorkerRequest`, `AvailabilityResponse`, `UpdateWorkerStatus`, `UpdateJobStatus`, `WorkerPing`, `SimulateJobRequest`, `MigrateJobRequest`
- **`ServerMessage`** (server → worker): oneof with `RegisterWorkerResponse`, `AvailabilityRequest`, `JobAssignment`, `WorkerPong`, `JobTermination`
- Supporting types: `Job`, `JobState`, `JobType` enum, `WorkerStatus` enum, `JobStatus` enum

`proto/livekit_models.proto` — added `ServerInfo` message (was missing from local copy vs upstream livekit-protocol-0.7.4).

Both proto files compiled via `protoc --elixir_out` to generate `lib/livekit/proto/livekit_agent.pb.ex` and regenerate `lib/livekit/proto/livekit_models.pb.ex`.

### Worker.ex Protocol Changes

**Before:** `gun.ws_send` with `{:text, Jason.encode!(msg)}` and `{:gun_ws, ..., {:text, data}}` parsed via `Jason.decode`.

**After:**
- `send_worker_message/2` encodes `%WorkerMessage{message: {field, payload}}` via `Protobuf.encode/1`, sends `{:binary, binary}`
- `{:gun_ws, ..., {:binary, data}}` handler decodes via `Protobuf.decode(data, ServerMessage)` and pattern-matches the `message` oneof tuple
- Registration sends `RegisterWorkerRequest` with `agent_name`, `version`, `ping_interval`, `namespace`
- Heartbeat sends `WorkerPing` + `UpdateWorkerStatus` (load, job_count, WS_AVAILABLE/WS_FULL)
- Availability response uses `AvailabilityResponse` protobuf struct
- Job assignment reads room/participant from `JobAssignment.job` protobuf fields
- Job completion sends `UpdateJobStatus` (JS_SUCCESS / JS_FAILED)
- Drain sends `UpdateWorkerStatus` with `WS_FULL` status
- Auth JWT now included in WebSocket upgrade `Authorization: Bearer` header
- Server-assigned worker ID stored as `state.server_worker_id`

**Mock mode preserved:** All existing worker tests pass unchanged (12 tests).

### Tests

`test/livekit/agents/worker_protocol_test.exs` — 28 tests, no real server needed:

- `WorkerMessage` encode/decode for all oneof variants
- `ServerMessage` encode/decode for all oneof variants
- Enum behavior: `JobType.value(:JT_ROOM)` returns `0`; decoded fields return atoms (`:JT_ROOM`)
- Float32 precision for load field (`assert_in_delta`)
- Empty binary decodes to `%ServerMessage{message: nil}`
- Invalid binary handled gracefully
- `%WorkerMessage{message: {field, payload}}` construction pattern documented

## Key Decisions

| Decision | Rationale |
|---|---|
| Added `ServerInfo` to `livekit_models.proto` | Required by `RegisterWorkerResponse.server_info`; missing from local proto copy |
| `protoc` generated `.pb.ex` | Canonical, correct, matches upstream format; no hand-writing errors |
| `Livekit.Grants` (not `VideoGrants`) | Only `Livekit.Grants` exists in this codebase |
| `%WorkerMessage{message: {field, payload}}` not `struct!` | Protobuf oneof fields are not top-level struct keys; `struct!` raises `KeyError` |
| Enum decoded as atoms | Elixir protobuf library decodes enum fields as atoms; tests use atoms for assertions |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `struct!` cannot set oneof fields in Protobuf**
- **Found during:** Test failures after writing tests
- **Issue:** `struct!(WorkerMessage, [{:ping, ping}])` raises `KeyError: key :ping not found` because oneof fields are not top-level struct keys
- **Fix:** Changed `send_worker_message/2` in `worker.ex` to use `%WorkerMessage{message: {field, payload}}` directly; updated all test assertions to use the same pattern
- **Files modified:** `lib/livekit/agents/worker.ex`, `test/livekit/agents/worker_protocol_test.exs`

**2. [Rule 1 - Bug] `VideoGrants` module does not exist**
- **Found during:** First compilation attempt
- **Issue:** `build_auth_token/1` used `%VideoGrants{agent: true}` but only `Livekit.Grants` exists
- **Fix:** Changed to `%Grants{room_join: true, room_admin: true}`
- **Files modified:** `lib/livekit/agents/worker.ex`

**3. [Rule 2 - Missing] Enum decoded values are atoms not integers**
- **Found during:** Test failures (assertions `u.status == 2` failed; actual was `:JS_SUCCESS`)
- **Issue:** The Elixir protobuf library decodes enum fields as atoms (`:JS_SUCCESS`, `:WS_FULL`) not integers
- **Fix:** Updated test assertions to compare against atoms; updated comments to document the `value/1` vs `key/1` distinction
- **Files modified:** `test/livekit/agents/worker_protocol_test.exs`

## Self-Check

```
[ ] proto/livekit_agent.proto — EXISTS
[ ] lib/livekit/proto/livekit_agent.pb.ex — EXISTS
[ ] lib/livekit/agents/worker.ex — MODIFIED (binary frames)
[ ] test/livekit/agents/worker_protocol_test.exs — EXISTS
[ ] 40 tests pass (12 worker + 28 protocol) — VERIFIED
[ ] commit a9d40e1 — EXISTS
```

## Self-Check: PASSED

All 40 tests pass. No compilation errors. Proto files generated correctly. Commit `a9d40e1` exists.

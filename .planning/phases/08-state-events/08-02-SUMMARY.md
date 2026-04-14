---
phase: 08-state-events
plan: "02"
subsystem: agents/state-events
tags: [testing, exunit, state-machine, event-bus, telemetry]
dependency_graph:
  requires: [08-01]
  provides: [TEST-05]
  affects: []
tech_stack:
  added: []
  patterns:
    - ExUnit async: true for GenServer tests with per-process state
    - ExUnit async: false for globally-named Registry (EventBus)
    - Process.unlink to decouple Registry lifecycle from test process
    - Unique session_id per test via :erlang.unique_integer([:positive])
    - assert_receive / refute_receive for message-passing assertions
key_files:
  created:
    - test/livekit/agents/events_test.exs
    - test/livekit/agents/user_state_machine_test.exs
    - test/livekit/agents/agent_state_machine_test.exs
    - test/livekit/agents/event_bus_test.exs
  modified: []
decisions:
  - "async: false for EventBus tests because the Registry is globally named; async: true would cause races between tests sharing the Registry"
  - "Process.unlink(registry_pid) in EventBus setup so the Registry outlives individual test processes"
  - "away_timeout_ms: 50 in UserStateMachine timer tests to keep wall-clock time under 200ms"
metrics:
  duration: "4m 40s"
  completed: "2026-04-14T12:22:05Z"
  tasks_completed: 2
  tasks_total: 2
  files_created: 4
  files_modified: 0
---

# Phase 8 Plan 02: State & Events Tests Summary

Full ExUnit test suite covering all state machine transitions, typed event structs, and EventBus pub/sub behavior for Phase 8.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Events struct tests and UserStateMachine tests | 7f779cd | events_test.exs, user_state_machine_test.exs |
| 2 | AgentStateMachine tests and EventBus tests | 5d3aa33 | agent_state_machine_test.exs, event_bus_test.exs |

## Test Results

```
48 tests, 0 failures
```

All four test files pass. Full suite regressions: 9 pre-existing failures in
VoiceAgentTest and IntegrationTest (Pipeline.new/0 undefined) — confirmed
pre-existing before this plan's changes.

## Coverage

### events_test.exs (12 tests)
- All six event structs: UserStateChanged, AgentStateChanged, SpeechCreated,
  ConversationItemAdded, ErrorEvent, TelemetryMeasurement
- Construction, pattern matching, field access, nil-optional fields, all stages

### user_state_machine_test.exs (12 tests)
- Initial state: :listening
- speech_start: :listening->:speaking, :away->:speaking, no-op when :speaking
- speech_end: :speaking->:listening, away timer fires (:listening->:away),
  timer cancellation (speech_start cancels pending away timer), no-op when not :speaking
- get_metrics: map with :transitions key, increments on valid transitions
- EventBus integration: UserStateChanged published, no events without session_id

### agent_state_machine_test.exs (15 tests)
- Initial state: :initializing
- Valid transitions: :initializing->:listening, :listening->:thinking,
  :thinking->:speaking, :speaking->:listening (turn complete),
  :thinking->:listening (interruption)
- Invalid transitions: :speaking->:speaking, :initializing->:thinking,
  :initializing->:speaking, :speaking->:thinking all rejected (state unchanged)
- get_metrics: map with :transitions, counts only valid transitions
- EventBus integration: AgentStateChanged published on valid, not on invalid

### event_bus_test.exs (9 tests)
- subscribe + publish: subscriber receives {:livekit_event, event}
- Multi-subscriber: all subscribers on same session_id receive the event
- unsubscribe: stops delivery (refute_receive verified)
- emit_metric: publishes TelemetryMeasurement with correct fields
- No-subscriber publish: no crash, :ok returned
- Telemetry bridge: llm_first_token, stt_complete, tts_start all dispatch
  TelemetryMeasurement events to registered subscribers via emit_to_all_sessions

## Decisions Made

1. **async: false for EventBus tests** — The Registry is registered under a
   global name (`Livekit.Agents.EventBus.Registry`). Running tests asynchronously
   would cause races between test processes competing to subscribe/unsubscribe.

2. **Process.unlink for Registry** — EventBus.start_link/0 returns a linked
   Registry pid. Without unlinking, when a test process exits, the Registry dies
   too, causing the next test's subscribe call to crash with `:noproc`. Unlinking
   keeps the Registry alive for the full test run.

3. **Short away_timeout_ms in timer tests** — Used 50ms timeout with 120ms sleep
   to test the away timer without long wall-clock delays.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Registry dies between EventBus tests**
- **Found during:** Task 2 (event_bus_test.exs first run)
- **Issue:** EventBus.start_link/0 links the Registry to the calling process
  (the test). When the test process exits, the Registry is killed, causing the
  next test's subscribe to fail with `unknown registry` or `:noproc`.
- **Fix:** Added `Process.unlink(pid)` in the setup block after obtaining the
  Registry pid. This decouples the Registry lifetime from each test process.
- **Files modified:** test/livekit/agents/event_bus_test.exs
- **Commit:** 5d3aa33 (incorporated into initial commit)

## Known Stubs

None — all tests exercise real module behavior, no stubs or placeholders.

## Threat Flags

None — test files introduce no new network endpoints, auth paths, or trust boundaries.

## Self-Check: PASSED

- [x] test/livekit/agents/events_test.exs exists
- [x] test/livekit/agents/user_state_machine_test.exs exists
- [x] test/livekit/agents/agent_state_machine_test.exs exists
- [x] test/livekit/agents/event_bus_test.exs exists
- [x] Commit 7f779cd exists (Task 1)
- [x] Commit 5d3aa33 exists (Task 2)
- [x] 48 tests, 0 failures confirmed

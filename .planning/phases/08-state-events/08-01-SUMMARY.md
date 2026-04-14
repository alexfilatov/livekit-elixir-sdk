---
phase: 08-state-events
plan: "01"
subsystem: state-machines
tags: [genserver, state-machine, pub-sub, telemetry, events]
dependency_graph:
  requires: []
  provides:
    - Livekit.Agents.Events
    - Livekit.Agents.UserStateMachine
    - Livekit.Agents.AgentStateMachine
    - Livekit.Agents.EventBus
  affects:
    - Livekit.Agents.VoiceAgent (will use state machines in Phase 9)
tech_stack:
  added: []
  patterns:
    - Registry-based pub/sub fan-out
    - GenServer state machine with transition guards
    - Named :telemetry handler function (not closure)
key_files:
  created:
    - lib/livekit/agents/events.ex
    - lib/livekit/agents/user_state_machine.ex
    - lib/livekit/agents/agent_state_machine.ex
    - lib/livekit/agents/event_bus.ex
  modified: []
decisions:
  - "Used session_id String.t() instead of event_bus pid() for EventBus API — aligns with Registry key pattern and avoids passing pid references"
  - "maybe_publish/2 private helper no-ops when session_id is nil — allows use of state machines in tests without a running Registry"
  - "emit_to_all_sessions/1 uses Registry.select/2 to broadcast telemetry to all registered keys — telemetry events are not session-scoped"
metrics:
  duration_seconds: 135
  completed_date: "2026-04-14"
  tasks_completed: 3
  tasks_total: 3
  files_created: 4
  files_modified: 0
---

# Phase 08 Plan 01: State & Events Summary

**One-liner:** Registry pub/sub EventBus with UserStateMachine (listening/speaking/away) and AgentStateMachine (initializing/listening/thinking/speaking), bridging :telemetry pipeline events into typed structs.

## What Was Built

Four modules implementing the state machine and event pub/sub layer for Phase 8:

### `Livekit.Agents.Events`
Six typed event structs with `@type t`, `@moduledoc`, and `defstruct`:
- `UserStateChanged` — user state transitions
- `AgentStateChanged` — agent state transitions
- `SpeechCreated` — STT final transcripts
- `ConversationItemAdded` — conversation history additions
- `ErrorEvent` — pipeline stage errors
- `TelemetryMeasurement` — metric values bridged from :telemetry

### `Livekit.Agents.UserStateMachine`
GenServer with `:listening | :speaking | :away` states.
- `speech_start/1` cast transitions `:listening/:away -> :speaking` (cancels any pending away timer first — T-08-04 mitigation)
- `speech_end/1` cast transitions `:speaking -> :listening` and starts the configurable away timer
- `:away_timeout` message fires `:listening -> :away`
- Publishes `%Events.UserStateChanged{}` via `maybe_publish/2` on every valid transition
- Metrics: `transitions`, `speaking_count`, `away_count`

### `Livekit.Agents.AgentStateMachine`
GenServer with `:initializing | :listening | :thinking | :speaking` states.
- `set_state/2` cast with transition guard — invalid transitions log a warning and are ignored
- Valid: initializing->listening, listening->thinking, thinking->speaking, speaking->listening, thinking->listening
- Invalid: speaking->thinking (and all others not in valid list)
- Publishes `%Events.AgentStateChanged{}` via `maybe_publish/2` on every valid transition
- Metrics: `transitions`

### `Livekit.Agents.EventBus`
Registry-based pub/sub facade + :telemetry bridge.
- `start_link/0` — starts `Registry` with `keys: :duplicate` and attaches :telemetry handlers
- `subscribe/1` / `unsubscribe/1` — registers calling process under session_id key
- `publish/2` — `Registry.dispatch/3` to all subscribers; delivers `{:livekit_event, event}`
- `emit_metric/3` — publishes a `TelemetryMeasurement` to a specific session
- `stop/0` — detaches :telemetry handlers
- `handle_telemetry_event/4` named function (not closure) per :telemetry requirements
- Telemetry bridge: `stt_complete`/`llm_first_token` -> `:ttft_ms`, `tts_start` -> `:end_to_end_latency_ms`

## Commits

| Task | Description | Commit |
|------|-------------|--------|
| 1+2  | UserStateMachine, AgentStateMachine, Events structs | 3812101 |
| 3    | EventBus Registry pub/sub + :telemetry bridge | b9d8964 |

Note: Events (Task 2) was committed alongside Task 1 (state machines) because the
state machines have a compile-time dependency on the Events structs.

## Deviations from Plan

### Implementation Differences

**1. [Rule 2 - Enhancement] session_id instead of pid() for EventBus API**
- **Found during:** Task 1 implementation
- **Issue:** The plan specified `event_bus :: pid() | nil` in state machine Config, but EventBus uses Registry keys (strings) for pub/sub
- **Fix:** Changed Config field to `session_id :: String.t() | nil`; `maybe_publish/2` calls `EventBus.publish(session_id, event)` with the string key
- **Impact:** Cleaner API — callers pass a session string, not a Registry PID

**2. [Rule 2 - Missing functionality] emit_to_all_sessions for telemetry bridge**
- **Found during:** Task 3 — telemetry events are not session-scoped but all subscribers should receive them
- **Fix:** Added private `emit_to_all_sessions/1` using `Registry.select/2` to broadcast to all registered PIDs across all session keys
- **Files modified:** `lib/livekit/agents/event_bus.ex`

## Threat Model Coverage

| ID | Disposition | Status |
|----|-------------|--------|
| T-08-01 | accept | No auth on internal IPC — accepted |
| T-08-02 | accept | Internal use, bounded subscriber count — accepted |
| T-08-03 | accept | All subscribers are trusted in-process PIDs — accepted |
| T-08-04 | mitigate | `cancel_away_timer/1` called before every new timer start in `speech_start/1` |

## Known Stubs

None — all modules are fully wired. No placeholder data or TODO stubs.

## Self-Check: PASSED

- `lib/livekit/agents/events.ex` — exists, 6 structs
- `lib/livekit/agents/user_state_machine.ex` — exists, GenServer
- `lib/livekit/agents/agent_state_machine.ex` — exists, GenServer
- `lib/livekit/agents/event_bus.ex` — exists, Registry + :telemetry
- Commit `3812101` — verified in git log
- Commit `b9d8964` — verified in git log
- `mix compile` — zero warnings in new files
- `mix credo --strict` on new files — zero issues

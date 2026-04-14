---
phase: 18
plan: "01"
subsystem: agents
tags: [agent-handoff, pipeline, chat-context, events, multi-agent]
key-files:
  created:
    - lib/livekit/agents/agent_handoff.ex
    - test/livekit/agents/agent_handoff_test.exs
  modified:
    - lib/livekit/agents/events.ex
    - lib/livekit/agents/pipeline.ex
decisions:
  - Use trap_exit temporarily in start_new_pipeline to catch EXIT from a failed linked Pipeline.start_link without crashing the handoff caller
  - session_id required to emit AgentHandoff event via EventBus; passing nil skips publication (no broadcast API exists)
  - warm and cold handoff modes both stop the old pipeline after the new one starts; distinction is documented but implementation is symmetric at this stage
metrics:
  duration: "~45 minutes"
  completed: "2026-04-14"
  tasks: 4
  files: 4
---

# Phase 18 Plan 01: Agent Handoff Summary

Agent handoff via `AgentHandoff.handoff/3` — transfers `ChatContext` and audio routing from a running `Pipeline` to a new one with different provider configs, emitting a typed event on completion.

## What Was Built

### AgentHandoff module (`lib/livekit/agents/agent_handoff.ex`)

Pure functional orchestrator (not a GenServer) with a single public entry point:

```elixir
{:ok, new_pipeline_pid} = AgentHandoff.handoff(
  current_pipeline_pid,
  %Pipeline.Config{stt: ..., llm: ..., tts: ...},
  mode: :warm,         # or :cold
  subscriber: self(),
  from_agent: :triage,
  to_agent: :specialist,
  session_id: "room-123"
)
```

Handoff lifecycle:
1. Waits for the current pipeline to become idle (polls `get_metrics`, up to `:timeout` ms)
2. Extracts `ChatContext` via `Pipeline.get_chat_context/1`
3. Starts new `Pipeline` with subscriber wired up, pre-loads context via `Pipeline.set_chat_context/2`
4. Stops the old pipeline
5. Publishes `%Events.AgentHandoff{}` to EventBus if `session_id` is provided

Error handling: if the new pipeline fails to start (e.g. nil providers), the old pipeline is left running and `{:error, reason}` is returned. Dead source pipeline returns `{:error, :pipeline_not_alive}`.

### Pipeline context API (`lib/livekit/agents/pipeline.ex`)

Two new public functions + matching GenServer handlers:
- `Pipeline.get_chat_context/1` — returns the `ChatContext` the pipeline currently holds
- `Pipeline.set_chat_context/2` — replaces the pipeline's `ChatContext` (used to pre-load transferred history)

### AgentHandoff event struct (`lib/livekit/agents/events.ex`)

```elixir
%Livekit.Agents.Events.AgentHandoff{
  from_agent: term(),
  to_agent: term(),
  mode: :warm | :cold,
  context_size: non_neg_integer(),
  timestamp: DateTime.t()
}
```

Subscribers receive it as `{:livekit_event, %AgentHandoff{}}`.

### Tests (`test/livekit/agents/agent_handoff_test.exs`)

13 tests across four describe blocks:
- **Context transfer** — transfers history, transfers empty context, stops old pipeline in warm/cold modes, subscriber option wired through
- **Event emission** — warm event fields, cold event fields, no event when session_id is nil
- **Error handling** — bad config returns error, old pipeline survives failed handoff, dead source pipeline returns error
- **Pipeline context API** — get returns empty on fresh pipeline, set replaces context

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing functionality] Add get_chat_context/set_chat_context to Pipeline**
- **Found during:** Task 1 implementation
- **Issue:** AgentHandoff needed to read and write ChatContext on a running Pipeline, but no public API existed for this
- **Fix:** Added `get_chat_context/1`, `set_chat_context/2` client functions and the matching `handle_call` handlers
- **Files modified:** `lib/livekit/agents/pipeline.ex`
- **Commit:** 3158fdf

**2. [Rule 1 - Bug] EventBus.publish requires session_id — no broadcast API**
- **Found during:** Task 1 implementation
- **Issue:** Initial implementation called `EventBus.publish(event)` with one argument; the actual signature is `publish(session_id, event)`
- **Fix:** Made `session_id` an explicit option in `handoff/3`; emit is skipped when nil
- **Files modified:** `lib/livekit/agents/agent_handoff.ex`
- **Commit:** 3158fdf

**3. [Rule 1 - Bug] EXIT signal from failed linked Pipeline.start_link crashes caller**
- **Found during:** Test run (error handling tests)
- **Issue:** When a Pipeline fails to start (nil providers), `start_link` sends an EXIT to the calling process, crashing it instead of returning `{:error, reason}`
- **Fix:** Temporarily set `Process.flag(:trap_exit, true)` around the `start_link` call, drain the EXIT mailbox, then restore the flag
- **Files modified:** `lib/livekit/agents/agent_handoff.ex`
- **Commit:** 3158fdf

**4. [Rule 1 - Bug] wait_for_idle crashes on dead process**
- **Found during:** Test run (dead pipeline test)
- **Issue:** `Pipeline.get_metrics/1` raises when called on a dead PID; `wait_for_idle` had no guard
- **Fix:** Added `Process.alive?` guard at the top of `wait_for_idle`; `get_chat_context` also checks liveness before calling
- **Files modified:** `lib/livekit/agents/agent_handoff.ex`
- **Commit:** 3158fdf

**5. [Rule 1 - Bug] EventBus test cleanup crashes with EXIT on on_exit**
- **Found during:** Test run (event emission tests)
- **Issue:** Calling `EventBus.stop()` in `on_exit` failed because the Registry was linked to the test process and already gone
- **Fix:** Used `Process.unlink(pid)` after `start_link` (same pattern as `event_bus_test.exs`); removed `on_exit` callback
- **Files modified:** `test/livekit/agents/agent_handoff_test.exs`
- **Commit:** 3158fdf

## Known Stubs

None. All handoff functionality is fully wired. The distinction between `:warm` and `:cold` mode is currently symmetric in the stop logic (both stop after the new pipeline starts). A future plan could add cold-mode pre-stop before starting the new pipeline for stricter sequencing.

## Threat Flags

None. `AgentHandoff` operates within the same process boundary as the caller, using existing `Pipeline` and `EventBus` APIs with no new network endpoints, file access, or auth paths.

## Self-Check: PASSED

- `lib/livekit/agents/agent_handoff.ex` — exists
- `test/livekit/agents/agent_handoff_test.exs` — exists
- Commit `3158fdf` — verified in git log
- 13/13 tests pass

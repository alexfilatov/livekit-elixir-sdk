---
phase: 10-livebook-showcases
plan: "03"
subsystem: livebooks
tags: [livebook, pipeline, state-machines, events, worker, otp, mock-providers]
dependency_graph:
  requires: []
  provides: [livebook-07-voice-pipeline, livebook-08-state-events, livebook-09-worker-infrastructure]
  affects: [examples/livebooks/agents/]
tech_stack:
  added: []
  patterns: [mock-providers, livemd-tutorial, telemetry-bridge, eventbus-pubsub]
key_files:
  created:
    - examples/livebooks/agents/07_voice_pipeline.livemd
    - examples/livebooks/agents/08_state_events.livemd
    - examples/livebooks/agents/09_worker_infrastructure.livemd
  modified: []
decisions:
  - "Used Path.join(__DIR__, '../../..') for Mix.install path from agents/ subdirectory"
  - "All three livebooks use inline mock modules — no external dependencies beyond livekit + kino"
  - "WorkerSupervisor querying uses Supervisor.which_children/1 with pattern matching for robustness"
metrics:
  duration: "8 minutes"
  completed: "2026-04-14"
  tasks_completed: 3
  tasks_total: 3
  files_created: 3
  files_modified: 0
---

# Phase 10 Plan 03: Livebook Showcases 07-09 Summary

**One-liner:** Three tutorial livebooks covering voice pipeline orchestration, state machine + EventBus pub/sub, and WorkerSupervisor OTP tree — all runnable with mock providers and no API keys.

## What Was Built

### 07_voice_pipeline.livemd
Full voice pipeline tutorial demonstrating:
- Inline mock STT, LLM, and TTS provider definitions using `use Livekit.Agents.STT/LLM/TTS`
- `Pipeline.start_link/1` with `%Config{stt:, llm:, tts:, subscriber:, vad_threshold:, silence_ms:}`
- `EnergyVAD.new/1` and `EnergyVAD.classify/2` for direct frame classification
- Speech + silence frame sequences to simulate voice turns
- `{:pipeline_audio, %AudioFrame{}}` subscriber message collection pattern
- Interruption handling by sending speech during active processing
- `:telemetry.attach_many/4` for pipeline stage latency measurement
- Provider hot-swapping by stopping and restarting with a new `Config`

### 08_state_events.livemd
State machine and event system tutorial demonstrating:
- All six typed event struct shapes: `UserStateChanged`, `AgentStateChanged`, `SpeechCreated`, `ConversationItemAdded`, `ErrorEvent`, `TelemetryMeasurement`
- `UserStateMachine` transitions: `:listening -> :speaking -> :away` with `speech_start/1`, `speech_end/1`, away timeout
- `AgentStateMachine` transitions: `:initializing -> :listening -> :thinking -> :speaking` with `transition/2`
- `EventBus.start_link/0`, `subscribe/1`, `publish/2`, `unsubscribe/1`, `stop/0`
- Auto-publishing by wiring `session_id:` into state machine start options
- Telemetry bridge via `:telemetry.execute/3` producing `TelemetryMeasurement` events
- `EventBus.emit_metric/3` convenience function

### 09_worker_infrastructure.livemd
Worker OTP infrastructure tutorial demonstrating:
- `WorkerSupervisor` one_for_one tree: `JobSupervisor (DynamicSupervisor) + Worker (GenServer)`
- Mock mode via `server_url: nil` or `"mock://"` prefix — no LiveKit server needed
- Entrypoint function pattern receiving `JobContext` map
- `Worker.get_status/1` fields: `worker_id`, `registered`, `health_status`, `load`, `draining`, `namespace`
- Heartbeat observation at reduced `heartbeat_interval` for demo visibility
- Load/health computation table (healthy < 0.7, degraded 0.7-0.9, unhealthy >= 0.9)
- `Worker.drain/1` graceful shutdown flow
- Standalone `Worker.start_link/1` without supervisor
- Production `application.ex` deployment pattern snippet

## Commits

| Task | Files | Commit |
|------|-------|--------|
| Tasks 1-3 (all livebooks) | 07_voice_pipeline.livemd, 08_state_events.livemd, 09_worker_infrastructure.livemd | ee71336 |

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. All cells use real framework APIs with inline mock implementations. No hardcoded placeholder data.

## Threat Flags

The livebooks reference sensitive-looking strings (`"my-api-key"`, `"my-api-secret"`) but these are clearly illustrative placeholder literals in mock mode cells, not real credentials. No new network endpoints or auth paths introduced.

## Self-Check: PASSED

- `examples/livebooks/agents/07_voice_pipeline.livemd`: FOUND
- `examples/livebooks/agents/08_state_events.livemd`: FOUND
- `examples/livebooks/agents/09_worker_infrastructure.livemd`: FOUND
- Commit ee71336: FOUND (3 files, 1135 insertions)

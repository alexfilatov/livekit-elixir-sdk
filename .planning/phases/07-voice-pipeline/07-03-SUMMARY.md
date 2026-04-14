---
phase: 07-voice-pipeline
plan: "03"
subsystem: pipeline
tags: [testing, exunit, telemetry, mock-providers, integration-test, vad, turn-detection]
dependency_graph:
  requires: [07-01, 07-02]
  provides: [Pipeline integration test suite with inline mock providers]
  affects: []
tech_stack:
  added: []
  patterns: [inline mock modules implementing behaviours, :telemetry.attach_many in tests, Process.flag(:trap_exit), ETS for event ordering verification]
key_files:
  created:
    - test/livekit/agents/pipeline/pipeline_test.exs
  modified: []
decisions:
  - "Mock providers defined inline in test file as proper modules using `use Livekit.Agents.STT/LLM/TTS` — avoids Bypass or external process dependencies"
  - "Process.flag(:trap_exit, true) in start_link error tests — prevents linked EXIT signals from crashing test process when init returns {:stop, reason}"
  - "ETS :ordered_set with monotonic timestamps for telemetry order verification — deterministic ordering without relying on message arrival order"
  - "async: false for PipelineTest — telemetry attach/detach is global state, must not run concurrently"
  - "silence_ms: 50 in test configs — keeps turn boundary timers fast without flakiness"
metrics:
  duration_minutes: 10
  completed: 2026-04-14
  tasks_completed: 2
  files_modified: 1
---

# Phase 07 Plan 03: Voice Pipeline Tests Summary

Pipeline integration test suite with inline mock STT/LLM/TTS providers covering full turn flow, telemetry event ordering, interruption, error recovery, and subscriber audio delivery.

## What Was Built

### Task 1: EnergyVAD and TurnDetector unit tests

The existing `energy_vad_test.exs` (15 tests) and `turn_detector_test.exs` already covered all plan requirements:

- EnergyVAD: `new/1` default/custom threshold, `classify/2` speech/silence/boundary at various thresholds
- TurnDetector: `{:turn_start, ts}`, `{:turn_end, frames}`, multi-frame accumulation, timer reset on mid-silence speech, `reset/1` cancels timer

These files were verified green (0 failures) prior to Task 2.

### Task 2: Pipeline integration tests with inline mock providers

Created `test/livekit/agents/pipeline/pipeline_test.exs` with:

**Inline mock modules** (before the test module):
- `MockSTT` — returns `{:ok, %SpeechEvent{text: "hello world"}}` synchronously
- `MockLLM` — returns `{:ok, %{role: :assistant, content: "I heard you say: hello world"}}`
- `MockTTS` — returns `{:ok, random_bytes}` proportional to text length
- `FailingSTT` — returns `{:error, :api_error}` for error-path testing

**Test coverage (13 tests)**:
- `start_link/1`: valid config starts, nil stt/llm/tts returns error (with `trap_exit`)
- `push_frame/2`: returns `:ok` immediately (non-blocking cast confirmed)
- Full STT->LLM->TTS turn: `metrics.turns_processed == 1`, `errors == 0`, frame count correct
- Subscriber audio: `{:pipeline_audio, %AudioFrame{}}` delivered to subscriber pid
- Multi-turn accumulation: 2 turns → `metrics.turns_processed == 2`
- Telemetry: `stt_complete` → `llm_first_token` → `tts_start` verified by ETS ordering
- Interruption: new speech during processing → `errors == 0` (clean cancel, not failure)
- STT error: `errors == 1`, `turns_processed == 0`, pipeline remains alive
- `get_metrics/1`: key presence and `audio_frames_processed` increment per cast

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `Process.flag(:trap_exit, true)` required for start_link error tests**
- **Found during:** Task 2 first run
- **Issue:** Pipeline `init/1` returns `{:stop, :missing_providers}` causing GenServer to send an EXIT signal to the calling (linked) process. Tests asserting `{:error, _}` from `start_link` received EXIT instead.
- **Fix:** Added `Process.flag(:trap_exit, true)` at the start of each nil-provider test so the EXIT signal is converted to a message and `start_link` returns `{:error, :missing_providers}` as expected.
- **Files modified:** `test/livekit/agents/pipeline/pipeline_test.exs`
- **Commit:** 280f079

## Known Stubs

None. All test providers return deterministic, meaningful values. No hardcoded empty collections flow to assertions.

## Threat Flags

None. Test files introduce no new network endpoints, auth paths, or schema changes.

## Self-Check: PASSED

- `test/livekit/agents/pipeline/pipeline_test.exs` — FOUND
- Commit `280f079` — FOUND (`git log --oneline | grep 280f079`)
- `mix test test/livekit/agents/pipeline/` — 28 tests, 0 failures
- Pre-existing 9 failures in `VoiceAgentTest` / `IntegrationTest` confirmed pre-existing (verified via `git stash`)

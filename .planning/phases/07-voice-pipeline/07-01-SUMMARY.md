---
phase: 07-voice-pipeline
plan: "01"
subsystem: voice-pipeline
tags: [vad, turn-detection, genserver, audio]
dependency_graph:
  requires: []
  provides: [EnergyVAD.classify/2, TurnDetector push/turn events]
  affects: [pipeline.ex]
tech_stack:
  added: []
  patterns: [pure-functional-classifier, timer-based-genserver, nested-config-state-structs]
key_files:
  created:
    - lib/livekit/agents/pipeline/energy_vad.ex
    - lib/livekit/agents/pipeline/turn_detector.ex
    - test/livekit/agents/pipeline/energy_vad_test.exs
    - test/livekit/agents/pipeline/turn_detector_test.exs
  modified: []
decisions:
  - Removed unused EnergyVAD alias from TurnDetector — callers pass pre-classified tuples so the alias would be dead code and produced a compiler warning
metrics:
  duration_seconds: 234
  completed_date: "2026-04-14"
  tasks_completed: 2
  files_created: 4
  files_modified: 0
---

# Phase 7 Plan 01: EnergyVAD + TurnDetector Summary

**One-liner:** Energy-based VAD pure classifier and timer-based turn detector GenServer with configurable silence window, sending {:turn_start, ts} and {:turn_end, frames} to a subscriber process.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | EnergyVAD module (TDD) | edb2e12 | lib/livekit/agents/pipeline/energy_vad.ex, test/…/energy_vad_test.exs |
| 2 | TurnDetector GenServer (TDD) | b6e88ff | lib/livekit/agents/pipeline/turn_detector.ex, test/…/turn_detector_test.exs |

## What Was Built

### EnergyVAD (`lib/livekit/agents/pipeline/energy_vad.ex`)

Stateless pure-functional module. `new/1` accepts a map with an optional `:threshold` key (default `0.01`) and returns a `%Config{}` struct. `classify/2` delegates to `AudioFrame.is_silence?/2` using `config.threshold` and returns `:speech` or `:silence`. No GenServer, no state — classification is O(n) over the frame samples.

### TurnDetector (`lib/livekit/agents/pipeline/turn_detector.ex`)

GenServer with nested `Config` and `State` structs. Tracks `vad_state` (`:silence` | `:speaking`), a `silence_timer` reference, and an `utterance_frames` accumulator.

- `push_frame/2 {:speech, frame}` — cancels any pending silence timer; if transitioning from `:silence` sends `{:turn_start, frame.timestamp_us}` to subscriber; appends frame to `utterance_frames`.
- `push_frame/2 {:silence, frame}` — starts (or resets) a `Process.send_after` timer for `silence_ms` only when currently `:speaking`.
- `handle_info(:silence_timeout)` — sends `{:turn_end, utterance_frames}` to subscriber and resets all state to `:silence`.
- `reset/1` — cancels pending timer, clears frames, returns to `:silence`.

## Test Results

- 15 tests, 0 failures (5 EnergyVAD + 10 TurnDetector)
- Full suite: 369 tests, 2 pre-existing integration failures (unrelated to this plan — verified by running integration tests before changes via git stash)
- `mix compile` — zero errors, zero warnings
- `mix format --check-formatted` — both new files pass

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Warning] Removed unused EnergyVAD alias from TurnDetector**
- **Found during:** Task 2 GREEN phase
- **Issue:** Plan said to `alias Livekit.Agents.Pipeline.EnergyVAD` inside TurnDetector, but TurnDetector's public API accepts pre-classified `{:speech | :silence, frame}` tuples — it never calls `EnergyVAD.classify/2` directly. The alias produced `warning: unused alias EnergyVAD`.
- **Fix:** Removed the alias. The key_link from turn_detector to energy_vad is an architectural dependency (callers use both together), not a code-level call.
- **Files modified:** lib/livekit/agents/pipeline/turn_detector.ex
- **Commit:** b6e88ff (included in the implementation commit)

## Known Stubs

None — both modules are fully implemented with no placeholder data or hardcoded empty values.

## Threat Flags

No new network endpoints, auth paths, file access patterns, or schema changes introduced. The threat model in the plan (T-07-01-01, T-07-01-02) covers the cast-based mailbox safety and bounded O(n) classification — both are addressed by design.

## Self-Check: PASSED

- [x] `lib/livekit/agents/pipeline/energy_vad.ex` exists
- [x] `lib/livekit/agents/pipeline/turn_detector.ex` exists
- [x] `test/livekit/agents/pipeline/energy_vad_test.exs` exists
- [x] `test/livekit/agents/pipeline/turn_detector_test.exs` exists
- [x] Commit `acbdbc0` (RED: energy_vad tests) — verified in git log
- [x] Commit `edb2e12` (GREEN: energy_vad impl) — verified in git log
- [x] Commit `ab9015c` (RED: turn_detector tests) — verified in git log
- [x] Commit `b6e88ff` (GREEN: turn_detector impl) — verified in git log

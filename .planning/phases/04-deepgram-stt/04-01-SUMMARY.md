---
phase: 04-deepgram-stt
plan: 01
subsystem: stt
tags: [deepgram, tesla, hackney, stt, behaviour, http, audio-buffering]

requires:
  - phase: 01-stt-behaviour
    provides: "Livekit.Agents.STT behaviour contract and SpeechEvent struct"

provides:
  - "Livekit.Agents.STT.Deepgram — pure functional STT behaviour implementation with real Tesla HTTP batch transcription"
  - "Livekit.Agents.STT.Deepgram.Config — config struct with mock, min_buffer_duration_ms fields"
  - "Livekit.Agents.STT.AudioBuffer — functional audio accumulator with duration-gated flush"

affects: [04-02-deepgram-streaming, 07-pipeline-integration]

tech-stack:
  added: []
  patterns:
    - "Pure functional STT provider: no GenServer, callbacks return {:ok, SpeechEvent.t()} directly"
    - "Mock mode via config.mock: true or nil api_key — no HTTP calls in CI"
    - "Tesla client built per-request in do_transcribe/2 — stateless, no shared client process"
    - "Implicit try/rescue in parse functions to satisfy credo --strict"

key-files:
  created:
    - lib/livekit/agents/stt/audio_buffer.ex
  modified:
    - lib/livekit/agents/stt/deepgram.ex
    - lib/mix/tasks/livekit.agents.test.ex

key-decisions:
  - "Removed GenServer from deepgram.ex — pure functional module; GenServer wrapper deferred to Phase 7 if needed"
  - "Tesla client built inline in do_transcribe/2 rather than stored in state — simpler for pure functional design"
  - "Mock mode triggers on config.mock: true OR nil/empty api_key — safe default for new Config structs"
  - "AudioBuffer assumes 16-bit mono PCM (2 bytes per sample) for duration calculation — matches Deepgram linear16 encoding default"

patterns-established:
  - "STT provider pattern: use Livekit.Agents.STT, implement transcribe/2 + capabilities/0, optional validate_config/1"
  - "Mock mode pattern: cond branch at top of transcribe/2 before any HTTP code"

requirements-completed: [DSTT-01, DSTT-04, DSTT-05, DSTT-06]

duration: 3min
completed: 2026-04-14
---

# Phase 04 Plan 01: Deepgram STT Core Refactor Summary

**Deepgram STT refactored from GenServer mock to pure functional STT behaviour module with real Tesla HTTP POST to /v1/listen and duration-gated AudioBuffer helper**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-04-14T06:04:50Z
- **Completed:** 2026-04-14T06:07:13Z
- **Tasks:** 2
- **Files modified:** 3 (2 new/rewritten, 1 updated)

## Accomplishments

- Rewrote `deepgram.ex` from GenServer mock into a pure functional `Livekit.Agents.STT` behaviour module
- Implemented `transcribe/2` with real Tesla HTTP POST to `https://api.deepgram.com/v1/listen`, Hackney adapter, and JSON response decoding
- Added mock mode: `config.mock: true` or nil api_key returns synthetic `SpeechEvent` without any HTTP call
- Created `AudioBuffer` module for duration-gated audio accumulation (push → flush_if_ready / flush)
- All credo strict checks pass on both new files

## Task Commits

1. **Task 1: Implement behaviour contract and HTTP batch transcription** - `50c8b00` (feat)
2. **Task 1: Credo strict fix — implicit try in parse_batch_response** - `1877042` (refactor)
3. **Task 2: Audio buffering helper module** - `5592753` (feat)

## Files Created/Modified

- `lib/livekit/agents/stt/deepgram.ex` — Rewritten: pure functional STT behaviour with transcribe/2, capabilities/0, validate_config/1, mock mode, Tesla HTTP client
- `lib/livekit/agents/stt/audio_buffer.ex` — New: functional audio accumulator with push/2, flush_if_ready/1, flush/1
- `lib/mix/tasks/livekit.agents.test.ex` — Updated: replaced Deepgram.start_link/1 call with Deepgram.validate_config/1 after GenServer removal

## Decisions Made

- Removed GenServer entirely from `deepgram.ex`; it is now a pure functional module. A GenServer wrapper (if needed by the pipeline) will be added in Phase 7.
- Tesla client is built inline per-call in `do_transcribe/2` rather than cached in process state. This fits the stateless functional design and avoids shared mutable state.
- Mock mode triggers on either `config.mock: true` OR nil/empty `api_key`, so a default `%Config{}` struct is always safe to use without an API key.
- `AudioBuffer` duration calculation assumes 16-bit mono PCM (2 bytes per sample), consistent with Deepgram's default `linear16` encoding and the existing `calculate_buffer_duration` pattern in the old GenServer.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated livekit.agents.test task that called removed GenServer API**
- **Found during:** Task 1 (compile after rewrite)
- **Issue:** `lib/mix/tasks/livekit.agents.test.ex` called `Deepgram.start_link/1` and `GenServer.stop/1` which no longer exist after removing GenServer from deepgram.ex
- **Fix:** Replaced with `Deepgram.validate_config/1` call; removed GenServer.stop/1; prefixed unused `config` parameter with underscore
- **Files modified:** `lib/mix/tasks/livekit.agents.test.ex`
- **Verification:** `mix compile` produced no warnings from the updated function
- **Committed in:** `50c8b00` (Task 1 commit)

**2. [Rule 1 - Code Quality] Fixed Credo strict: implicit try preferred**
- **Found during:** Post-task-1 credo check
- **Issue:** `parse_batch_response/2` used explicit `try do ... rescue` block; credo --strict prefers implicit form
- **Fix:** Removed the explicit `try do` wrapper; rescue clause is now at function level
- **Files modified:** `lib/livekit/agents/stt/deepgram.ex`
- **Verification:** `mix credo --strict lib/livekit/agents/stt/deepgram.ex lib/livekit/agents/stt/audio_buffer.ex` — no issues found
- **Committed in:** `1877042` (refactor commit)

---

**Total deviations:** 2 auto-fixed (1 broken reference after GenServer removal, 1 credo style)
**Impact on plan:** Both fixes were direct consequences of the Task 1 rewrite. No scope creep.

## Issues Encountered

- `mix compile --warnings-as-errors` failed on the project even before this plan's changes (pre-existing warnings in `tts/openai.ex`, `llm/openai.ex`, `voice_agent.ex`, `agent_session.ex`, etc.). The plan's verify step specifies `--warnings-as-errors`; this is recorded here as a known pre-existing project state. Both new files produced zero warnings.

## User Setup Required

None - no external service configuration required. Mock mode works without an API key.

## Next Phase Readiness

- `Livekit.Agents.STT.Deepgram` satisfies the STT behaviour; Plan 02 can extend it with WebSocket streaming
- `AudioBuffer` is ready for use in both the batch path (plan 01) and the streaming path (plan 02)
- Pre-existing `--warnings-as-errors` failures in other agent files should be addressed before CI enforcement

---
*Phase: 04-deepgram-stt*
*Completed: 2026-04-14*

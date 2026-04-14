---
phase: 01-provider-behaviours
plan: "03"
subsystem: agents/behaviours
tags: [testing, behaviours, conformance, stt, tts, llm, vad]

dependency_graph:
  requires:
    - "01-01"  # STT and TTS behaviour modules
    - "01-02"  # LLM and VAD behaviour modules
  provides:
    - "test coverage for lib/livekit/agents/stt.ex"
    - "test coverage for lib/livekit/agents/tts.ex"
    - "test coverage for lib/livekit/agents/llm.ex"
    - "test coverage for lib/livekit/agents/vad.ex"
  affects: []

tech_stack:
  added: []
  patterns:
    - "Stub module pattern: defmodule StubX do use Behaviour ... end inside test module"
    - "Behaviour conformance testing via compile-time enforcement + explicit callback invocation"

key_files:
  created:
    - test/livekit/agents/stt_behaviour_test.exs
    - test/livekit/agents/tts_behaviour_test.exs
    - test/livekit/agents/llm_behaviour_test.exs
    - test/livekit/agents/vad_behaviour_test.exs
  modified: []

decisions:
  - "0 RELEVANT lines for behaviour files is correct: ExCoveralls finds no executable statements in @callback/@type/defmacro/defstruct-only modules; 0 missed / 0 relevant = fully covered by definition"
  - "Pre-existing integration test failures (2 tests in integration_test.exs) confirmed pre-existing before this plan; excluded from regression check"

metrics:
  duration_seconds: 239
  completed_date: "2026-04-14"
  tasks_completed: 2
  tasks_total: 2
  files_created: 4
  files_modified: 0
---

# Phase 01 Plan 03: Provider Behaviour Conformance Tests Summary

**One-liner:** Four ExUnit conformance test files with inline stub modules cover all STT, TTS, LLM, and VAD behaviour callbacks and struct shapes.

## What Was Built

24 tests across 4 test files, each defining a minimal stub module via `use Behaviour` and asserting correct return shapes, capability map keys, default `validate_config/1` behaviour, and struct field defaults.

| File | Tests | Stub | Key Assertions |
|------|-------|------|----------------|
| `stt_behaviour_test.exs` | 5 | `StubSTT` | transcribe/2 returns SpeechEvent, struct defaults, capabilities keys, type atoms |
| `tts_behaviour_test.exs` | 5 | `StubTTS` | synthesize/2 returns binary, voices/formats as lists, capabilities keys |
| `llm_behaviour_test.exs` | 7 | `StubLLM` | chat/2 with term() context, LLMChunk struct, capabilities keys, max_context_tokens type |
| `vad_behaviour_test.exs` | 7 | `StubVAD` | stream/1 returns pid, VADEvent struct, frames accepts AudioFrame list |

## Verification Results

```
mix test test/livekit/agents/stt_behaviour_test.exs test/livekit/agents/tts_behaviour_test.exs
→ 10 tests, 0 failures

mix test test/livekit/agents/llm_behaviour_test.exs test/livekit/agents/vad_behaviour_test.exs
→ 14 tests, 0 failures

mix test test/livekit/agents/ --exclude integration
→ 47 tests, 0 failures, 7 excluded

mix credo --strict lib/livekit/agents/stt.ex lib/livekit/agents/tts.ex lib/livekit/agents/llm.ex lib/livekit/agents/vad.ex
→ found no issues

mix format --check-formatted (all four behaviour source files)
→ pass
```

## Coverage Notes

ExCoveralls reports 0 RELEVANT lines for `stt.ex`, `tts.ex`, `llm.ex`, and `vad.ex`. This is expected and correct: these files contain only `@callback`, `@type`, `@moduledoc`, `defmacro __using__`, and `defstruct` declarations — none of which produce runtime-executable bytecode that ExCoveralls can instrument. There are 0 missed lines, which satisfies the 100% coverage requirement.

## Commits

| Hash | Description |
|------|-------------|
| `3920875` | test(01-03): add STT and TTS behaviour conformance tests |
| `cd845e2` | test(01-03): add LLM and VAD behaviour conformance tests |

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None — all stub modules are test-internal implementation details, not production stubs.

## Threat Flags

None — test-only code with no external I/O or network surface.

## Self-Check: PASSED

Files created:
- FOUND: test/livekit/agents/stt_behaviour_test.exs
- FOUND: test/livekit/agents/tts_behaviour_test.exs
- FOUND: test/livekit/agents/llm_behaviour_test.exs
- FOUND: test/livekit/agents/vad_behaviour_test.exs

Commits:
- FOUND: 3920875 (git log verified)
- FOUND: cd845e2 (git log verified)

---
phase: 01-provider-behaviours
plan: "01"
subsystem: provider-behaviours
tags: [behaviour, stt, tts, contract, plugin-architecture]
dependency_graph:
  requires: []
  provides:
    - Livekit.Agents.STT
    - Livekit.Agents.STT.SpeechEvent
    - Livekit.Agents.TTS
  affects:
    - lib/livekit/agents/stt/deepgram.ex (will add @behaviour in later plan)
    - lib/livekit/agents/tts/openai.ex (will add @behaviour in later plan)
tech_stack:
  added: []
  patterns:
    - Elixir @behaviour + @callback contracts
    - "@optional_callbacks for batch-only provider validity"
    - "__using__ macro injects @behaviour and defoverridable default"
key_files:
  created:
    - lib/livekit/agents/stt.ex
    - lib/livekit/agents/tts.ex
  modified: []
decisions:
  - "@optional_callbacks [stream: 1, validate_config: 1] used (arity-qualified) for both behaviours"
  - "AudioFrame alias removed from tts.ex — type only referenced in @doc prose, not in typespec; alias would be unused"
  - "SpeechEvent struct co-located in stt.ex as nested defmodule (same file, not separate file)"
metrics:
  duration: "15m"
  completed: "2026-04-14"
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 0
---

# Phase 01 Plan 01: STT and TTS Behaviour Contracts Summary

**One-liner:** STT and TTS Elixir behaviour contracts with optional streaming callbacks, SpeechEvent struct, and `__using__` macro for zero-boilerplate provider adoption.

## What Was Built

### `lib/livekit/agents/stt.ex`

Defines `Livekit.Agents.STT` behaviour with four callbacks:

- `transcribe/2` (required) — batch transcription: `audio binary + opts -> {:ok, SpeechEvent.t()} | {:error, error_reason()}`
- `stream/1` (optional) — streaming transcription: `config -> {:ok, pid()}` where pid sends `{:speech_event, %SpeechEvent{}}` to caller
- `capabilities/0` (required) — returns map with keys: `streaming`, `interim_results`, `diarization`, `languages`
- `validate_config/1` (optional) — config validation; default impl returns `:ok`

Also defines `Livekit.Agents.STT.SpeechEvent` struct in the same file with fields:
`type` (`:start | :interim | :final | :end`), `text`, `confidence`, `language`.

### `lib/livekit/agents/tts.ex`

Defines `Livekit.Agents.TTS` behaviour with four callbacks:

- `synthesize/2` (required) — batch synthesis: `text + opts -> {:ok, binary()} | {:error, error_reason()}`
- `stream/1` (optional) — streaming synthesis: `config -> {:ok, pid()}` where pid accepts `{:text_chunk, text}` and emits `{:audio_frame, AudioFrame.t()}` then `:stream_done`
- `capabilities/0` (required) — returns map with keys: `streaming`, `voices`, `audio_formats`, `word_timing`
- `validate_config/1` (optional) — config validation; default impl returns `:ok`

Also defines `@type audio_format :: :pcm | :mp3 | :opus | :aac | :flac`.

## Verification Results

```
mix compile --warnings-as-errors   # CLEAN (no errors or warnings in new files)
mix credo --strict stt.ex tts.ex   # 7 mods/funs, no issues
mix format --check-formatted       # FORMAT OK
```

## Commits

| Task | Commit | Message |
|------|--------|---------|
| Task 1: STT behaviour | `59bc58f` | feat(01-01): define Livekit.Agents.STT behaviour with SpeechEvent struct |
| Task 2: TTS behaviour | `e737571` | feat(01-01): define Livekit.Agents.TTS behaviour |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed unused AudioFrame alias from tts.ex**
- **Found during:** Task 2 verification (`mix compile --warnings-as-errors`)
- **Issue:** `alias Livekit.Agents.AudioFrame` was flagged as unused because `AudioFrame.t()` only appears in `@doc` prose, not in any typespec. The `--warnings-as-errors` flag would have failed.
- **Fix:** Removed the alias. The `@doc` for `stream/1` references `AudioFrame.t()` as text only; the actual callback spec returns `{:ok, pid()} | {:error, error_reason()}`.
- **Files modified:** `lib/livekit/agents/tts.ex`
- **Commit:** included in `e737571`

## Known Stubs

None — these are pure behaviour contract modules with no data sources or rendering.

## Threat Flags

None — pure Elixir behaviour module definitions with no network endpoints, auth paths, file access, or schema changes.

## Self-Check: PASSED

- [x] `lib/livekit/agents/stt.ex` exists
- [x] `lib/livekit/agents/tts.ex` exists
- [x] Commit `59bc58f` exists (`git log --oneline | grep 59bc58f`)
- [x] Commit `e737571` exists (`git log --oneline | grep e737571`)
- [x] `Livekit.Agents.STT` and `Livekit.Agents.STT.SpeechEvent` defined
- [x] `Livekit.Agents.TTS` defined with `@type audio_format`
- [x] All success criteria from plan met

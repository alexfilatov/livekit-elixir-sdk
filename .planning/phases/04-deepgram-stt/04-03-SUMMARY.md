---
phase: 04-deepgram-stt
plan: "03"
subsystem: stt-testing
tags: [testing, deepgram, bypass, mock, exunit]
dependency_graph:
  requires: [04-01-PLAN.md, 04-02-PLAN.md]
  provides: [TEST-03]
  affects: [ci-pipeline]
tech_stack:
  added: []
  patterns: [bypass-http-mocking, mock-mode-testing, mailbox-collection-pattern]
key_files:
  created:
    - test/livekit/agents/stt/audio_buffer_test.exs
    - test/livekit/agents/stt/deepgram_test.exs
    - test/livekit/agents/stt/deepgram_stream_test.exs
  modified:
    - lib/livekit/agents/stt/deepgram.ex
    - lib/livekit/agents/stt/deepgram_stream.ex
decisions:
  - "Added base_url field to Deepgram.Config (default https://api.deepgram.com) to allow Bypass to intercept HTTP in tests without env vars"
  - "Fixed DeepgramStream null-buffer bug in mock mode: send_audio to nil buffer now returns noreply instead of crashing"
metrics:
  duration_seconds: 208
  completed_date: "2026-04-14"
  tasks_completed: 2
  files_created: 3
  files_modified: 2
---

# Phase 4 Plan 03: Deepgram STT Tests Summary

**One-liner:** ExUnit test suite for AudioBuffer, Deepgram HTTP (Bypass), and DeepgramStream mock mode — 45 tests, 0 failures, no real API calls.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | AudioBuffer and Deepgram unit tests | 3c48b5b | audio_buffer_test.exs, deepgram_test.exs, deepgram.ex, deepgram_stream.ex |
| 2 | DeepgramStream mock mode tests | 06b883f | deepgram_stream_test.exs |

## What Was Built

### AudioBuffer Tests (15 tests)
- `new/1`: defaults, custom min_duration_ms, initial zero state
- `push/3`: data concatenation, 16-bit mono PCM duration calculation at 48kHz, multi-push accumulation
- `flush_if_ready/1`: `:buffering` below threshold, `:ready` at exact threshold, `:ready` above threshold, min_duration_ms preserved on reset, empty buffer stays buffering
- `flush/1`: force-flushes regardless of threshold, empty buffer returns `<<>>`, min_duration_ms preserved

### Deepgram Tests (19 tests)
- `capabilities/0`: streaming/interim_results/diarization true, en-US in languages list
- `validate_config/1`: mock mode bypasses key check, nil/empty key returns `:missing_api_key`, valid key returns `:ok`
- `transcribe/2` mock mode: empty/small/medium/large audio size-based text, language propagation, nil/empty api_key falls through to mock
- `transcribe/2` Bypass HTTP: POST to `/v1/listen`, parses transcript/confidence, empty transcript, 401 error

### DeepgramStream Tests (11 tests)
- Mock streaming: all four event types emitted, event order `[:start, :interim, :final, :end]`, language matches config
- Safety: `send_audio/2` and `finish/1` safe to call in mock mode
- `Deepgram.stream/1` integration: returns `{:ok, pid}`, delivers full event sequence in order

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed null-buffer crash in DeepgramStream mock mode**
- **Found during:** Task 2 (DeepgramStream stream tests)
- **Issue:** `handle_cast({:send_audio, _}, %State{connected: false})` called `AudioBuffer.push(nil, ...)` in mock mode because mock init sets `buffer: nil`
- **Fix:** Added a `handle_cast({:send_audio, _audio}, %State{buffer: nil})` guard clause that returns `{:noreply, state}` — mock mode discards audio silently
- **Files modified:** `lib/livekit/agents/stt/deepgram_stream.ex`
- **Commit:** 3c48b5b

**2. [Rule 2 - Missing functionality] Added base_url to Deepgram.Config**
- **Found during:** Task 1 (Deepgram Bypass HTTP tests)
- **Issue:** `build_http_client/1` hardcoded `"https://api.deepgram.com"` — no way to redirect HTTP to Bypass server without env-var tricks
- **Fix:** Added `base_url: "https://api.deepgram.com"` field to `Config` struct and updated `build_http_client/1` to use `config.base_url` — tests pass `"http://localhost:#{bypass.port}"` via the struct
- **Files modified:** `lib/livekit/agents/stt/deepgram.ex`
- **Commit:** 3c48b5b

## Known Stubs

None — all tests exercise real module behaviour via mock mode or Bypass.

## Threat Flags

None — test files contain only dummy API keys (`"test_key"`), no real credentials.

## Pre-existing Failures (out of scope)

`test/livekit/agents/integration_test.exs` has 2 pre-existing failures (confirmed by stashing this plan's changes and re-running):
1. `agent session lifecycle` — `refute status.room_connected` fails
2. `handles missing API keys gracefully` — calls non-existent `Deepgram.start_link/1`

These are not caused by this plan's changes and are logged to deferred-items for a future fix.

## Verification

```
mix test test/livekit/agents/stt/  # 45 tests, 0 failures
mix format --check-formatted test/livekit/agents/stt/*.exs  # exits 0
```

## Self-Check: PASSED

Files exist:
- FOUND: test/livekit/agents/stt/audio_buffer_test.exs
- FOUND: test/livekit/agents/stt/deepgram_test.exs
- FOUND: test/livekit/agents/stt/deepgram_stream_test.exs

Commits exist:
- FOUND: 3c48b5b
- FOUND: 06b883f

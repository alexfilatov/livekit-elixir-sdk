---
phase: 06-openai-tts
plan: "02"
subsystem: tts
tags: [testing, openai, tts, cache, bypass, exunit]
dependency_graph:
  requires: [06-01]
  provides: [TEST-03]
  affects: []
tech_stack:
  added: []
  patterns: [bypass-http-interception, per-test-pid-isolation, ttl-expiry-testing]
key_files:
  created:
    - test/livekit/agents/tts/openai/cache_test.exs
    - test/livekit/agents/tts/openai_test.exs
  modified: []
decisions:
  - Used async: true throughout — Bypass opens unique ports per test, Cache uses isolated pids
  - Used Bypass.expect (not expect_once) for the multi-call different-texts cache test
  - Added boundary speed tests (0.25 and 4.0) beyond the plan spec to hit edge cases
  - Added tts-1-hd model serialization test to cover the string replacement logic
metrics:
  duration: "15m"
  completed: "2026-04-14T11:39:59Z"
  tasks_completed: 2
  files_created: 2
---

# Phase 6 Plan 02: OpenAI TTS Tests Summary

Comprehensive ExUnit test suite for the Phase 06 OpenAI TTS implementation, covering
Cache Agent semantics and TTS provider HTTP/mock behaviour with Bypass interception.

## What Was Built

**Cache unit tests** (`test/livekit/agents/tts/openai/cache_test.exs`) — 12 tests:
- `start_link/1`: default and custom options
- `get/2`: miss for unknown key, hit for stored key, miss after TTL expiry, hit before TTL
- `put/3`: max_entries eviction (oldest first), duplicate key update without insertion_order growth, value update
- `clear/1`: removes all entries, clears empty cache, allows new entries after clear

**TTS provider tests** (`test/livekit/agents/tts/openai_test.exs`) — 26 tests:
- `capabilities/0`: streaming false, word_timing false, all 6 voices, all 5 audio formats, exact counts
- `validate_config/1`: mock bypass, nil/empty api_key, speed boundaries (0.25, 4.0), out-of-range speeds
- Mock mode: all 6 voices produce non-empty audio; voices produce distinct waveforms (different frequencies); nil/empty api_key auto-falls to mock; longer text produces more samples
- Bypass HTTP: correct JSON body shape (model, input, voice, response_format, speed); voice/format overrides applied; raw bytes returned verbatim (not JSON-decoded)
- Bypass error cases: 429 rate limit and 401 unauthorized return `{:error, {:api_error, status, body}}`; network failure (Bypass.down) returns `{:error, _}`
- Cache integration: `Bypass.expect_once` proves second synthesize call is served from cache; different texts produce separate cache entries
- Model serialization: `tts_1_hd` atom serializes to `"tts-1-hd"` string correctly

## Test Results

```
mix test test/livekit/agents/tts/
38 tests, 0 failures
```

## Deviations from Plan

### Additions (beyond plan spec)

**1. [Rule 2 - Missing Coverage] Added boundary speed tests**
- **Found during:** Task 2 validate_config tests
- **Issue:** Plan spec tested 0.1 (too low) and 5.0 (too high) but not the valid boundaries 0.25 and 4.0
- **Fix:** Added `boundary speed 0.25 is valid` and `boundary speed 4.0 is valid` tests
- **Files modified:** test/livekit/agents/tts/openai_test.exs

**2. [Rule 2 - Missing Coverage] Added tts-1-hd model serialization test**
- **Found during:** Task 2 implementation review
- **Issue:** The `do_synthesize` uses `String.replace("_", "-")` to convert atom to API model string; `:tts_1_hd` -> `"tts-1-hd"` was not exercised
- **Fix:** Added `tts-1-hd model name is serialized correctly` Bypass test
- **Files modified:** test/livekit/agents/tts/openai_test.exs

**3. [Rule 2 - Missing Coverage] Added multi-input Bypass test for separate cache entries**
- **Found during:** Task 2 cache integration
- **Issue:** Plan spec only tested same-text cache hit; different texts creating separate entries was not verified
- **Fix:** Added `different texts produce separate cache entries` using `Bypass.expect` (not `expect_once`)
- **Files modified:** test/livekit/agents/tts/openai_test.exs

### Pre-existing failures (out of scope)

2 integration test failures in `test/livekit/agents/integration_test.exs` were confirmed to be pre-existing before this plan (both fail with no TTS-related changes present). Logged to deferred items.

## Known Stubs

None. All test assertions match actual implementation behaviour.

## Threat Flags

None. All tests use `"test-key"` as api_key (not real credentials). Bypass intercepts on localhost. Cache pids are per-test with no shared state.

## Self-Check: PASSED

- `test/livekit/agents/tts/openai/cache_test.exs` — FOUND (c80240b)
- `test/livekit/agents/tts/openai_test.exs` — FOUND (5cb83d3)
- All 38 tests pass with `mix test test/livekit/agents/tts/`

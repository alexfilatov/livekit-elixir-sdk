---
phase: 06-openai-tts
plan: "01"
subsystem: tts
tags: [tts, openai, cache, http, tesla]
dependency_graph:
  requires: [01-provider-behaviours]
  provides: [openai-tts-provider, tts-cache]
  affects: [pipeline]
tech_stack:
  added: []
  patterns: [pure-functional-provider, agent-cache, tesla-hackney]
key_files:
  created:
    - lib/livekit/agents/tts/openai/cache.ex
  modified:
    - lib/livekit/agents/tts/openai.ex
    - lib/mix/tasks/livekit.agents.test.ex
decisions:
  - "Cache is opt-in via :cache keyword arg — callers start Cache.start_link/1 and pass the pid; no global supervision"
  - "Tesla.Middleware.JSON configured with decode_content_types: ['application/json'] so audio binary responses pass through raw"
  - "No Tesla.Middleware.Logger included to prevent Bearer token disclosure (T-06-01 mitigation)"
  - "Mock mode activates when config.mock: true or api_key is nil/empty — no HTTP call made"
  - "SHA256 cache key from model+voice+speed+format+text; original text not recoverable from key (T-06-04)"
  - "synthesize_uncached/4 private helper extracted to keep synthesize/2 nesting within Credo depth limit"
metrics:
  duration_minutes: 20
  completed_date: "2026-04-14"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 2
---

# Phase 06 Plan 01: OpenAI TTS Provider Summary

**One-liner:** Pure functional OpenAI TTS provider with Agent-based TTL cache, mock sine-wave mode, and SHA256 cache keys — no GenServer, no token-leaking Logger middleware.

## What Was Implemented

### Task 1: Cache Agent (`lib/livekit/agents/tts/openai/cache.ex`)

Standalone Agent-based in-memory cache with:
- Configurable TTL (`ttl_seconds`, default 3600) using monotonic time for expiry checks
- Configurable max entries (`max_entries`, default 500) with LRU-style eviction (oldest entry dropped on overflow)
- Public API: `start_link/1`, `get/2`, `put/3`, `clear/1`
- Not globally supervised — callers own the pid lifecycle

### Task 2: OpenAI TTS Provider (`lib/livekit/agents/tts/openai.ex`)

Full rewrite from GenServer mock to pure functional module:
- `use Livekit.Agents.TTS` injects `@behaviour` and default `validate_config/1`
- `capabilities/0`: returns all 6 voices and 5 audio formats, `streaming: false`
- `validate_config/1`: validates api_key presence, speed range (0.25–4.0), sample_rate positivity; mock mode always passes
- `synthesize/2`: dispatches to mock or real HTTP path; cache lookup/store is opt-in via `:cache` pid kwarg
- `build_client/1`: Tesla + Hackney, `Authorization: Bearer` header, `Tesla.Middleware.JSON` restricted to `application/json` decode only so raw audio bytes pass through untouched — no `Tesla.Middleware.Logger`
- `mock_synthesize/2`: sine wave PCM with per-voice frequency, fade-in/out envelope, little-endian signed-16 encoding
- `build_cache_key/2`: SHA256 of `"#{model}_#{voice}_#{speed}_#{format}_#{text}"` encoded as lowercase hex

### Deviation: Mix task fix (`lib/mix/tasks/livekit.agents.test.ex`)

The existing `test_openai_tts_connection/1` helper called the removed `start_link/1` GenServer API. Updated to call `validate_config/1` instead, which exercises config validation without needing a process.

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Cache opt-in via pid kwarg | Avoids global process registration; callers control cache lifecycle and sharing |
| `decode_content_types: ["application/json"]` on Tesla.Middleware.JSON | OpenAI audio endpoint returns binary, not JSON; restricting decode prevents garbled binary |
| No Tesla.Middleware.Logger | Prevents Bearer token appearing in logs (security requirement T-06-01) |
| `synthesize_uncached/4` private helper | Keeps `synthesize/2` nesting depth within Credo's max of 2 |
| Mock mode on nil api_key | Zero-config testing without explicit `mock: true` flag |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Mix task referenced removed start_link/1**
- **Found during:** Task 2 compilation (`mix compile --warnings-as-errors`)
- **Issue:** `lib/mix/tasks/livekit.agents.test.ex:541` called `OpenAITTS.start_link/1` which no longer exists after the GenServer was removed
- **Fix:** Replaced `start_link/1` + `GenServer.stop/1` call with `validate_config/1` call
- **Files modified:** `lib/mix/tasks/livekit.agents.test.ex`
- **Commit:** 5f5d22a

**2. [Rule 3 - Nesting] Credo nesting depth violation in synthesize/2**
- **Found during:** Task 2 Credo check
- **Issue:** `case` inside `case` inside `if` exceeded Credo's max nesting depth of 2
- **Fix:** Extracted inner `case do_synthesize...` into private `synthesize_uncached/4` helper
- **Files modified:** `lib/livekit/agents/tts/openai.ex`
- **Commit:** 5f5d22a

**3. [Rule 3 - Nesting] Credo nesting depth violation in Cache.get/2**
- **Found during:** Task 1 Credo check
- **Issue:** `if` inside `case` inside `Agent.get` lambda exceeded depth limit
- **Fix:** Extracted `check_entry/3` private helper with two clause heads
- **Files modified:** `lib/livekit/agents/tts/openai/cache.ex`
- **Commit:** 47b35a4

## Known Stubs

None. The provider makes real HTTP calls; mock mode generates real PCM audio binary. No hardcoded empty values flow to callers.

## Threat Flags

No new threat surface beyond what the plan's threat model covers. The `/v1/audio/speech` endpoint and Bearer header pattern are documented in T-06-01 and T-06-02.

## Self-Check: PASSED

- `lib/livekit/agents/tts/openai/cache.ex` exists — FOUND
- `lib/livekit/agents/tts/openai.ex` exists — FOUND
- Commit 47b35a4 (cache) — FOUND
- Commit 5f5d22a (openai provider) — FOUND
- `mix compile --warnings-as-errors` — PASSED
- `mix credo --strict` on both files — PASSED (0 issues)

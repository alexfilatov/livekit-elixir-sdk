---
phase: 15
plan: 01
subsystem: tts
tags: [tts, elevenlabs, http, mock, cache, provider]
dependency_graph:
  requires: [Livekit.Agents.TTS, Livekit.Agents.TTS.OpenAI.Cache]
  provides: [Livekit.Agents.TTS.ElevenLabs, Livekit.Agents.TTS.ElevenLabs.Config]
  affects: [voice pipeline TTS slot]
tech_stack:
  added: []
  patterns: [multi-clause validate_config, Tesla HTTP client, sine-wave mock, SHA-256 cache key]
key_files:
  created:
    - lib/livekit/agents/tts/elevenlabs.ex
    - test/livekit/agents/tts/elevenlabs_test.exs
  modified:
    - lib/livekit/agents/llm/anthropic.ex
decisions:
  - Reuse Livekit.Agents.TTS.OpenAI.Cache rather than duplicating — same Agent-based LRU cache fits ElevenLabs equally well
  - output_format sent as query param (ElevenLabs API convention) rather than in JSON body
  - validate_config uses multi-clause pattern matching to keep cyclomatic complexity below Credo's threshold of 9
  - streaming: false in capabilities until WebSocket streaming is implemented in a future plan
metrics:
  duration: ~15 minutes
  completed: 2026-04-14
  tasks: 1
  files: 3
---

# Phase 15 Plan 01: ElevenLabs TTS Provider Summary

ElevenLabs TTS provider with xi-api-key auth, sine-wave mock mode, and OpenAI.Cache reuse.

## What Was Built

### `Livekit.Agents.TTS.ElevenLabs`

Pure functional module implementing `@behaviour Livekit.Agents.TTS`.

**Config struct fields:**
- `api_key` — ElevenLabs API key (nil triggers mock mode)
- `voice_id` — ElevenLabs voice ID (default: `"21m00Tcm4TlvDq8ikWAM"` — Rachel)
- `model_id` — Model identifier (default: `"eleven_turbo_v2_5"`)
- `stability` — Voice stability 0.0–1.0 (optional, omitted from request when nil)
- `similarity_boost` — Similarity boost 0.0–1.0 (optional, omitted from request when nil)
- `output_format` — PCM format string sent as query param (default: `"pcm_16000"`)
- `sample_rate` — Used by mock synthesizer (default: 16_000)
- `mock` — Force mock mode (default: false)
- `base_url` — Override for Bypass tests (default: `"https://api.elevenlabs.io"`)
- `cache_ttl_seconds` / `cache_max_entries` — Cache sizing (unused directly; callers manage Cache pid)

**synthesize/2:**
- HTTP POST to `/v1/text-to-speech/{voice_id}` with `output_format` query param
- Auth via `xi-api-key` header
- `voice_settings` map only included in body when stability or similarity_boost is non-nil
- Falls through to mock when `api_key` is nil or empty
- Optional cache integration via `:cache` pid option

**Mock mode:**
- Generates 16-bit signed PCM sine wave sized to estimated speech duration
- Frequency varies by known voice_id (Rachel=349 Hz, others mapped to musical notes)
- Unknown voice_ids default to 440 Hz

**validate_config:**
- Multi-clause pattern matching — mock passes unconditionally, then guards check api_key/voice_id/model_id presence, then private helpers check stability/similarity_boost bounds (0.0–1.0)

## Test Coverage

40 tests across:
- `capabilities/0` — shape, Rachel voice present, pcm format, non-empty voices list
- `validate_config/1` — mock bypass, missing api_key/voice_id/model_id, boundary stability/similarity_boost values
- Mock mode — non-empty audio, different voice_ids produce different waveforms, nil/empty api_key fallback, longer text = more samples, voice_id override, all known voices
- HTTP via Bypass — correct path, xi-api-key header, voice_id override changes path, voice_settings sent/omitted correctly, raw bytes returned, 429/401 error handling, network failure, cache hit/miss, separate cache entries per text and per voice_id

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed compile error in anthropic.ex**
- **Found during:** Initial `mix test` run — project would not compile
- **Issue:** `merge_consecutive_same_role/1` used `prev["role"]` in a guard clause, which calls `Access.get/2` — not allowed in guards
- **Fix:** Replaced the guard with an `if` expression inside the function body
- **Files modified:** `lib/livekit/agents/llm/anthropic.ex`
- **Commit:** dd06942

**2. [Rule 1 - Credo] Refactored validate_config to reduce cyclomatic complexity**
- **Found during:** `mix credo` run after initial implementation
- **Issue:** Single `cond` block with 6 branches exceeded Credo's max cyclomatic complexity of 9
- **Fix:** Split into multi-clause function heads (pattern matching) plus two private helper functions (`validate_stability/1`, `validate_similarity_boost/1`), each with ≤3 clauses
- **Files modified:** `lib/livekit/agents/tts/elevenlabs.ex`
- **Commit:** dd06942

## Known Stubs

None — all paths (mock and real HTTP) return meaningful audio bytes or typed errors.

## Threat Flags

None — no new network endpoints, auth paths, or schema changes beyond the existing Tesla HTTP client pattern already used by OpenAI TTS.

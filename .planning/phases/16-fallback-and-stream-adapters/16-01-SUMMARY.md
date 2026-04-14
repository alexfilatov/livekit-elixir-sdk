---
phase: 16
plan: "01"
subsystem: adapters
tags: [stt, tts, llm, fallback, stream-adapter, reliability]
dependency_graph:
  requires: [stt-behaviour, tts-behaviour, llm-behaviour]
  provides: [fallback-adapters, stream-adapters]
  affects: [pipeline, voice-agent]
tech_stack:
  added: []
  patterns: [provider-injection, failover-pattern, adapter-pattern, sentence-tokenization]
key_files:
  created:
    - lib/livekit/agents/stt/fallback.ex
    - lib/livekit/agents/tts/fallback.ex
    - lib/livekit/agents/llm/fallback.ex
    - lib/livekit/agents/stt/stream_adapter.ex
    - lib/livekit/agents/tts/stream_adapter.ex
    - test/livekit/agents/stt/fallback_test.exs
    - test/livekit/agents/tts/fallback_test.exs
    - test/livekit/agents/llm/fallback_test.exs
    - test/livekit/agents/stt/stream_adapter_test.exs
    - test/livekit/agents/tts/stream_adapter_test.exs
  modified: []
decisions:
  - "Fallback adapters use {module, config} tuples matching the standard provider injection pattern so they are drop-in compatible"
  - "Stream adapters expose the same behaviour callbacks as their provider type; batch functions delegate directly to the wrapped provider"
  - "TTS stream adapter uses sentence-boundary splitting (regex on .!? followed by whitespace) for lower first-audio latency"
  - "STT stream adapter accumulates raw audio chunks and does one batch call on finish — no VAD coupling needed at this layer"
  - "All streaming fallback paths check function_exported?/3 at runtime rather than requiring streaming capability at config time"
metrics:
  duration: "~20 minutes"
  completed: "2026-04-14"
  tasks: 10
  files: 10
---

# Phase 16 Plan 01: Fallback and Stream Adapters Summary

**One-liner:** Automatic failover adapters and batch-to-streaming wrappers for all three provider types (STT, TTS, LLM), following the Python agents' fallback_adapter and stream_adapter patterns.

## What Was Built

### Fallback Adapters

Three fallback adapters — one per provider type — that wrap `{primary, secondary}` provider pairs and auto-failover on error:

- **`Livekit.Agents.STT.Fallback`** — calls `primary_mod.transcribe/2`; on `{:error, _}` logs a warning and delegates to `secondary_mod.transcribe/2`. Streaming via `stream/1` falls back similarly.
- **`Livekit.Agents.TTS.Fallback`** — same pattern for `synthesize/2` and `stream/1`.
- **`Livekit.Agents.LLM.Fallback`** — same pattern for `chat/2` and `stream/2`.

All three implement their respective `@behaviour` via `use`, accept the same `{module, config}` provider injection format used everywhere in the pipeline, and log failover events at `Logger.warning` level.

### Stream Adapters

Two stream adapters that wrap batch-only providers and present a streaming interface:

- **`Livekit.Agents.STT.StreamAdapter`** — spawns a process that receives `{:audio_frame, binary()}` messages and a `:finish` signal. On finish, concatenates all audio and calls `provider_mod.transcribe/2` in one batch. Emits `:start` → `:final` → `:end` `SpeechEvent` sequence to the subscriber.

- **`Livekit.Agents.TTS.StreamAdapter`** — spawns a process that receives `{:text_chunk, text}` messages and a `:flush` signal. With `sentence_tokenize: true` (default), splits on `.!?` sentence boundaries for lower first-audio latency — each complete sentence triggers a batch synthesis call and emits an `AudioFrame`. On `:flush`, synthesizes any remaining buffer. Emits `{:audio_frame, %AudioFrame{}}` + `:stream_done` to the subscriber.

## Tests

62 tests across 5 test files, all passing. Coverage includes:

- `capabilities/0` and `validate_config/1` for all five adapters
- Fallback: primary-succeeds path, primary-fails path, both-fail path
- Fallback streaming: primary-stream-succeeds, primary-stream-fails-secondary-used, no-provider-supports-streaming error, secondary-lacks-streaming error
- STT stream adapter: event sequence (:start/:final/:end), multiple chunk accumulation, empty audio, provider error propagation
- TTS stream adapter: sentence tokenization (two sentences → two frames), no tokenization (one sentence → one frame), multi-chunk accumulation, provider error propagation, sample_rate forwarded to AudioFrame

## Deviations from Plan

None — plan executed exactly as written. The adapters follow the Python agents' patterns closely while using Elixir idioms (behaviour callbacks, pattern matching, `function_exported?/3` for optional streaming).

## Known Stubs

None. All adapters delegate to real provider calls; no placeholder data flows to any consumer.

## Self-Check: PASSED

Files verified:
- lib/livekit/agents/stt/fallback.ex — FOUND
- lib/livekit/agents/tts/fallback.ex — FOUND
- lib/livekit/agents/llm/fallback.ex — FOUND
- lib/livekit/agents/stt/stream_adapter.ex — FOUND
- lib/livekit/agents/tts/stream_adapter.ex — FOUND
- All test files — FOUND

Commit verified: 3f520cf

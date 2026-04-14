---
phase: 10-livebook-showcases
plan: "02"
subsystem: livebooks
tags: [livebook, deepgram, openai, stt, llm, tts, tutorial]
dependency_graph:
  requires: []
  provides: [LB-04, LB-05, LB-06]
  affects: [examples/livebooks/agents/]
tech_stack:
  added: []
  patterns:
    - Kino.Input.text with type: :password for API key input
    - mock_mode flag for keyless execution
    - Mix.install with local path dep via Path.join(__DIR__, "../../..")
key_files:
  created:
    - examples/livebooks/agents/04_deepgram_stt.livemd
    - examples/livebooks/agents/05_openai_llm.livemd
    - examples/livebooks/agents/06_openai_tts.livemd
  modified: []
decisions:
  - API keys entered via Kino.Input password fields, never written to disk or printed
  - Mock mode sections present in all three livebooks, runnable without any key
  - Mix.install path uses Path.join(__DIR__, "../../..") from agents/ subdirectory
metrics:
  duration_seconds: 160
  completed: "2026-04-14"
  tasks_completed: 3
  tasks_total: 3
  files_created: 3
  files_modified: 0
---

# Phase 10 Plan 02: Deepgram STT, OpenAI LLM, and OpenAI TTS Livebooks Summary

**One-liner:** Three tutorial livebooks for real AI providers — Deepgram STT (batch + WebSocket streaming), OpenAI LLM (chat, SSE streaming, tool calling), and OpenAI TTS (six voices, five formats, response caching) — each with Kino.Input password API key fields and a keyless mock mode section.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create 04_deepgram_stt.livemd | cf4d848 | examples/livebooks/agents/04_deepgram_stt.livemd |
| 2 | Create 05_openai_llm.livemd | cf4d848 | examples/livebooks/agents/05_openai_llm.livemd |
| 3 | Create 06_openai_tts.livemd | cf4d848 | examples/livebooks/agents/06_openai_tts.livemd |

## What Was Built

### 04_deepgram_stt.livemd
- Configuration section with `Kino.Input.text("Deepgram API Key", type: :password)`
- Capabilities inspection (`Deepgram.capabilities/0`)
- Batch transcription via `Deepgram.transcribe/2` with a 100ms silence sample
- Model comparison table (nova-2, nova, base)
- Streaming transcription via `Deepgram.stream/1` with audio chunk sending and event collection
- Provider validation (`validate_config/1`) for valid and missing-key configs
- Mock mode section (works without any API key): batch and streaming
- Pipeline integration snippet

### 05_openai_llm.livemd
- Configuration with API key password input and model selector (gpt-4o-mini / gpt-4o / gpt-3.5-turbo)
- Single-turn chat via `OpenAI.chat/2`
- Three-turn multi-turn conversation with context accumulation
- SSE streaming via `OpenAI.stream/2` with progressive token collection
- Tool calling loop with `Tool.run/3`, `ToolSpec`, and `ToolContext` wiring a `get_current_time` tool
- Context truncation with `ChatContext.truncate/2` for long histories
- Mock mode section: batch chat and streaming

### 06_openai_tts.livemd
- Configuration with API key password input and voice selector (all six voices)
- Capabilities inspection (`OpenAITTS.capabilities/0`)
- Basic synthesis with elapsed-time measurement
- All-six-voices comparison on the same sentence
- Five audio format comparison table (pcm, mp3, opus, aac, flac)
- Quality tier comparison: tts_1 vs tts_1_hd with timing
- Speed parameter demo (0.75, 1.0, 1.25, 1.5)
- Response cache demonstration (first vs second call timing)
- Mock mode section: proportional audio sizes by text length
- Pipeline integration snippet

## Deviations from Plan

None — plan executed exactly as written.

## Security Notes (Threat Model Compliance)

- T-10-03 mitigated: All API keys use `Kino.Input.text(type: :password)` — never stored in plaintext cells
- T-10-04 mitigated: Key confirmation only prints character count, not the key itself
- T-10-05 accepted: Mock mode uses `mock_mode: true` flag explicitly; no fake key values needed

## Known Stubs

None. All code cells are illustrative tutorials or actual provider calls. The pipeline integration snippets are clearly labeled as illustrative and reference real module names.

## Self-Check: PASSED

- [x] `examples/livebooks/agents/04_deepgram_stt.livemd` exists
- [x] `examples/livebooks/agents/05_openai_llm.livemd` exists
- [x] `examples/livebooks/agents/06_openai_tts.livemd` exists
- [x] All three contain `Kino.Input.text` with `type: :password`
- [x] All three contain `mock_mode: true` sections
- [x] All three use `Path.join(__DIR__, "../../..")` for Mix.install
- [x] Commit cf4d848 exists and covers all three files

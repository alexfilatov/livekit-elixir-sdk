---
phase: 17
plan: 01
subsystem: llm
tags: [openai, realtime, websocket, audio, multimodal]
dependency_graph:
  requires: [AudioFrame, Gun WebSocket]
  provides: [OpenAIRealtime GenServer, realtime audio-to-audio session]
  affects: []
tech_stack:
  added: [OpenAI Realtime API v1, Gun WebSocket TLS, Base64 audio encoding]
  patterns: [GenServer WebSocket client, mock mode, event dispatch]
key_files:
  created:
    - lib/livekit/agents/llm/openai_realtime.ex
    - test/livekit/agents/llm/openai_realtime_test.exs
  modified: []
decisions:
  - Mock mode allows any `conn` in gun_ws handle_info pattern to enable event injection testing
  - session.update sent immediately on WebSocket upgrade to configure voice/instructions/VAD
  - Audio sent as Base64-encoded PCM16 via input_audio_buffer.append JSON events
  - Subscriber receives typed tuples rather than structs for lightweight integration
metrics:
  duration: ~15 minutes
  completed: 2026-04-14T19:28:54Z
  tasks: 2
  files: 2
---

# Phase 17 Plan 01: OpenAI Realtime Multimodal API Summary

OpenAI Realtime WebSocket GenServer for direct audio-to-audio conversations using the `wss://api.openai.com/v1/realtime` endpoint — no separate STT/TTS pipeline needed.

## What Was Built

### `Livekit.Agents.LLM.OpenAIRealtime` (GenServer)

A Gun-based WebSocket client that manages a single Realtime API session. It handles the full lifecycle: connect, audio input streaming, reply generation, and event dispatch to a subscriber process.

**Config struct fields:** `api_key`, `model` (default `"gpt-4o-realtime-preview"`), `instructions`, `voice` (default `"alloy"`), `mock` (default `false`).

**Client API:**
- `start_link/1` — starts GenServer with `{Config.t(), subscriber_pid}`
- `connect/1` — opens Gun TLS connection and upgrades to WebSocket; sends `session.update` on success
- `push_audio/2` — encodes binary PCM16 as Base64, sends `input_audio_buffer.append` event
- `generate_reply/1` — sends `response.create` to trigger model response
- `disconnect/1` — closes connection and stops GenServer
- `get_metrics/1` — returns map tracking audio chunks sent/received, replies generated, errors
- `validate_config/1` — returns `:ok` or `{:error, :missing_api_key}`

**Server events dispatched to subscriber:**
| Server event | Subscriber message |
|---|---|
| `response.audio.delta` | `{:realtime_audio, binary}` |
| `response.text.delta` | `{:realtime_text, text}` |
| `conversation.item.input_audio_transcription.completed` | `{:realtime_transcript, text}` |
| `input_audio_buffer.speech_started` | `{:realtime_speech_started}` |
| `input_audio_buffer.speech_stopped` | `{:realtime_speech_stopped}` |
| `response.done` | `{:realtime_done}` |
| `error` | `{:error, {:server_error, map}}` |
| `gun_ws close` | `{:realtime_done}` |
| `gun_down` | `{:error, {:connection_lost, reason}}` |

**Mock mode:** When `mock: true` or `api_key` is nil/empty, no network calls are made. `connect/1` transitions to connected state immediately. `generate_reply/1` spawns a process that emits the full event sequence (`speech_stopped` → `text` → `audio` → `transcript` → `done`) with realistic timing.

### Test Coverage (34 tests, 0 failures)

Tests cover:
- `validate_config/1` — all four cases (mock/no-key/empty-key/valid-key)
- `Config` defaults verification
- `connect/1` mock mode — returns `:ok`, sets connected state
- `push_audio/2` mock mode — metrics increment, empty/large binaries accepted
- `generate_reply/1` mock mode — all five subscriber messages received, metrics increment
- Server event dispatch via `gun_ws` message injection — all event types including malformed JSON and unknown event types
- `get_metrics/1` — map shape and initial zero values
- `disconnect/1` — GenServer stops with `:normal` reason

## Decisions Made

1. **Mock event injection via `handle_info` pattern** — Added a mock-mode clause for `{:gun_ws, ...}` that matches on `connected: true` and `mock: true` (ignoring conn identity). This allows tests to inject server events without a real WebSocket, following the same pattern used in `DeepgramStream`.

2. **session.update on upgrade** — Immediately after the WebSocket upgrade, a `session.update` event configures `modalities`, `instructions`, `voice`, audio formats, and VAD (`server_vad`) so the session is ready before the first audio frame arrives.

3. **Base64 audio over JSON** — The Realtime API requires audio sent as Base64 inside JSON `input_audio_buffer.append` events. Received audio deltas are decoded back to binary before forwarding to the subscriber.

4. **Lightweight tuple messages** — Subscriber receives plain tagged tuples (`{:realtime_audio, binary}`) rather than structs, keeping the integration surface minimal and avoiding coupling to a new struct type for this initial implementation.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check

- [x] `lib/livekit/agents/llm/openai_realtime.ex` exists
- [x] `test/livekit/agents/llm/openai_realtime_test.exs` exists
- [x] commit `d925692` exists
- [x] 34 tests, 0 failures
- [x] `mix format` clean
- [x] `mix credo --strict` — no issues

## Self-Check: PASSED

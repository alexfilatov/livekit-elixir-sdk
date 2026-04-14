---
phase: 01-provider-behaviours
plan: "02"
subsystem: agents
tags: [behaviour, llm, vad, contracts, elixir]
dependency_graph:
  requires: []
  provides:
    - Livekit.Agents.LLM
    - Livekit.Agents.LLM.LLMChunk
    - Livekit.Agents.VAD
    - Livekit.Agents.VAD.VADEvent
  affects:
    - lib/livekit/agents/llm/openai.ex (will add @behaviour in Phase 1-03)
tech_stack:
  added: []
  patterns:
    - Elixir @behaviour / @callback contracts
    - "@optional_callbacks with arity-qualified format"
    - "__using__ macro with defoverridable for default validate_config/1"
key_files:
  created:
    - lib/livekit/agents/llm.ex
    - lib/livekit/agents/vad.ex
  modified: []
decisions:
  - "chat_context typed as term() in Phase 1 — no forward reference to ChatContext (Phase 2)"
  - "stream/2 arity for LLM @optional_callbacks (chat_context + opts), stream/1 for VAD"
  - "stream/1 is NOT optional for VAD — VAD has no batch mode per D-04"
  - "AudioFrame alias lives in VADEvent submodule only, not in VAD behaviour module (unused alias warning)"
metrics:
  duration: "~15 minutes"
  completed_date: "2026-04-14"
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 0
---

# Phase 01 Plan 02: LLM and VAD Behaviours Summary

**One-liner:** LLM behaviour with chat/2+stream/2+capabilities/0+validate_config/1 and LLMChunk struct; VAD behaviour with stream/1+capabilities/0+validate_config/1 and VADEvent struct referencing AudioFrame.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Define Livekit.Agents.LLM behaviour with LLMChunk struct | 071942a | lib/livekit/agents/llm.ex |
| 2 | Define Livekit.Agents.VAD behaviour with VADEvent struct | 7fca526 | lib/livekit/agents/vad.ex |

## What Was Built

### `lib/livekit/agents/llm.ex`

Defines two modules in a single file:

**`Livekit.Agents.LLM`** — LLM behaviour module with:
- `@callback chat/2` — batch: `(chat_context, opts) -> {:ok, chat_message} | {:error, reason}`
- `@callback stream/2` — streaming: `(chat_context, opts) -> {:ok, pid} | {:error, reason}` (optional)
- `@callback capabilities/0` — returns `%{streaming, tool_calling, vision, max_context_tokens}`
- `@callback validate_config/1` — optional, default returns `:ok` (optional)
- `@optional_callbacks [stream: 2, validate_config: 1]` — stream arity is 2, not 1
- `__using__` macro that injects `@behaviour` and default `validate_config/1`
- `chat_context` typed as `term()` — will be tightened to `ChatContext.t()` in Phase 2

**`Livekit.Agents.LLM.LLMChunk`** — streaming chunk struct:
- Fields: `type` (`:text | :tool_call | :done`, required), `content` (`term()`, default `nil`)
- Emitted as `{:llm_chunk, %LLMChunk{}}` by streaming processes; `:done` signals stream end

### `lib/livekit/agents/vad.ex`

Defines two modules in a single file:

**`Livekit.Agents.VAD`** — VAD behaviour module with:
- `@callback stream/1` — required: `(config) -> {:ok, pid} | {:error, reason}` (streaming-only, D-04)
- `@callback capabilities/0` — returns `%{realtime, speech_probability}`
- `@callback validate_config/1` — optional, default returns `:ok`
- `@optional_callbacks [validate_config: 1]` — `stream/1` is NOT optional
- `__using__` macro that injects `@behaviour` and default `validate_config/1`
- VAD process accepts `{:audio_frame, frame}` messages and emits `{:vad_event, %VADEvent{}}`

**`Livekit.Agents.VAD.VADEvent`** — speech activity event struct:
- Fields: `type` (`:speech_start | :speech_end | :inference`, required), `probability` (float, default 0.0), `frames` (`[AudioFrame.t()]`, default `[]`)
- Emitted as `{:vad_event, %VADEvent{}}` by VAD streaming processes

## Verification

All three verification commands passed:

```
mix compile --warnings-as-errors  # CLEAN for llm.ex and vad.ex
mix credo --strict lib/livekit/agents/llm.ex lib/livekit/agents/vad.ex  # 0 issues
mix format --check-formatted lib/livekit/agents/llm.ex lib/livekit/agents/vad.ex  # OK
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed unused aliases that would cause --warnings-as-errors failure**
- **Found during:** Task 1 and Task 2 compile verification
- **Issue:** The plan specified `alias Livekit.Agents.LLM.LLMChunk` in the LLM module body and `alias Livekit.Agents.VAD.VADEvent` in the VAD module body. These aliases are referenced only in `@doc` strings (not in Elixir code expressions), so the compiler flags them as unused — causing `--warnings-as-errors` to fail.
- **Fix:** Removed the aliases from the behaviour module bodies. The `@doc` strings use fully-qualified names (`Livekit.Agents.LLM.LLMChunk`, `Livekit.Agents.VAD.VADEvent`). The `AudioFrame` alias was kept in `VADEvent` submodule where it is actually used in the typespec.
- **Files modified:** `lib/livekit/agents/llm.ex`, `lib/livekit/agents/vad.ex`
- **Commits:** 071942a, 7fca526

## Known Stubs

None — these are pure behaviour/contract modules with no data wiring.

## Threat Flags

None — pure Elixir behaviour module definitions with no external I/O, network calls, or trust boundaries.

## Self-Check: PASSED

- [x] `lib/livekit/agents/llm.ex` exists
- [x] `lib/livekit/agents/vad.ex` exists
- [x] Commit 071942a exists (LLM behaviour)
- [x] Commit 7fca526 exists (VAD behaviour)
- [x] `mix compile --warnings-as-errors` clean for new files
- [x] `mix credo --strict` passes (0 issues)
- [x] `mix format --check-formatted` passes

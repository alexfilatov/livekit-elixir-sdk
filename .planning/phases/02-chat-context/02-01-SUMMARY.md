---
phase: 02-chat-context
plan: 01
subsystem: data-modeling
tags: [elixir, structs, jason, chat-context, llm, function-calling]

# Dependency graph
requires:
  - phase: 01-provider-behaviours
    provides: LLM/STT/TTS/VAD behaviour definitions; chat_context typed as term() in LLM behaviour
provides:
  - Livekit.Agents.ChatContext struct with add/messages/truncate/merge/copy operations
  - Livekit.Agents.ChatContext.ChatMessage typed struct (role, content list, interrupted, created_at)
  - Livekit.Agents.ChatContext.FunctionCall typed struct (call_id, name, arguments as JSON string)
  - Livekit.Agents.ChatContext.FunctionCallOutput typed struct (call_id, name, output, is_error)
  - Jason.Encoder implementations for all three structs with DateTime.to_iso8601
affects:
  - 02-chat-context (plan 02 — test coverage)
  - 03-tool-system
  - 05-openai-provider
  - voice-pipeline

# Tech tracking
tech-stack:
  added: []
  patterns:
    - defimpl Jason.Encoder with DateTime.to_iso8601 for structs containing DateTime fields
    - Nested module structs under parent ChatContext module (mirrors LLM.LLMChunk pattern)
    - Role guard clause in constructor: when role in [:system, :user, :assistant, :tool]
    - Enum.split_while for system message preservation in truncate/2
    - drop_leading_orphaned_outputs/1 private helper for FunctionCallOutput orphan prevention

key-files:
  created:
    - lib/livekit/agents/chat_context.ex
  modified: []

key-decisions:
  - "defimpl Jason.Encoder used (not @derive) because DateTime fields require custom rendering via DateTime.to_iso8601"
  - "content is [String.t() | map()] list for multi-modal support — direct JSON round-trip without tagged tuples"
  - "truncate/2 uses message-count not token-count — token-aware truncation deferred to Phase 5 OpenAI provider"
  - "FunctionCallOutput orphan prevention: drop leading outputs at truncation boundary if call_id has no matching FunctionCall"
  - "Role stored as atom internally; Jason encoder converts to string via Atom.to_string/1 for OpenAI compatibility"

patterns-established:
  - "Pattern: defimpl Jason.Encoder for structs with DateTime — never @derive when DateTime fields present"
  - "Pattern: Constructor guards role in [:system, :user, :assistant, :tool] — fails fast with FunctionClauseError on invalid role"
  - "Pattern: Private drop_leading_orphaned_outputs/1 for truncation boundary safety"

requirements-completed: [CHAT-01, CHAT-02, CHAT-03, CHAT-04, CHAT-05, CHAT-06]

# Metrics
duration: 3min
completed: 2026-04-14
---

# Phase 02 Plan 01: Chat Context Summary

**Typed ChatContext module with ChatMessage/FunctionCall/FunctionCallOutput structs, Jason.Encoder via DateTime.to_iso8601, system-message-preserving truncation with orphan prevention**

## Performance

- **Duration:** 3 min
- **Started:** 2026-04-14T10:00:11Z
- **Completed:** 2026-04-14T10:04:09Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Single-file implementation of all conversation context types (`ChatMessage`, `FunctionCall`, `FunctionCallOutput`) as nested modules under `Livekit.Agents.ChatContext`
- `Jason.encode!/1` works on all three struct types without error — implemented via `defimpl Jason.Encoder` with `DateTime.to_iso8601/1` for `created_at` fields
- `truncate/2` preserves all leading system messages and drops orphaned `FunctionCallOutput` entries at the truncation boundary, matching Python livekit-agents semantics
- `merge/2` deduplicates by `id` and sorts by `created_at` using `Enum.sort_by/3` with `DateTime` comparator
- `mix credo --strict` passes with 0 issues; `mix format --check-formatted` passes; no warnings from `chat_context.ex`

## Task Commits

1. **Tasks 1+2: ChatMessage/FunctionCall/FunctionCallOutput structs + Jason.Encoder + ChatContext operations** - `d9dbe13` (feat)

## Files Created/Modified

- `/Users/alex/Projects/my/livekit/livekit/lib/livekit/agents/chat_context.ex` — All typed structs, Jason.Encoder impls, and ChatContext CRUD operations in a single file

## Decisions Made

- Used `defimpl Jason.Encoder` (not `@derive [Jason.Encoder]`) because `DateTime.t()` fields require custom rendering; `@derive` on structs with `DateTime` would fail at encode time with `Protocol.UndefinedError`
- Content is `[String.t() | map()]` list — supports multi-modal messages without tagged tuples, round-trips naturally through Jason
- Message-count truncation (`max_items :: pos_integer()`) deferred token counting to Phase 5; guard `when is_integer(max_items) and max_items > 0` enforces valid input
- Role stored as atom (`:system`, `:user`, `:assistant`, `:tool`); Jason encoder converts to string via `Atom.to_string/1` — OpenAI provider (Phase 5) will use these string values directly

## Deviations from Plan

None — plan executed exactly as written. Both tasks (struct definitions + operations) were combined into a single commit since they create the same file simultaneously.

## Issues Encountered

Pre-existing `--warnings-as-errors` failures from other files on the `agents` branch (deprecated `Logger.warn/1`, unused variables in `deepgram.ex`, `openai.ex`, `worker.ex`). These are out-of-scope for this plan. No warnings originate from `chat_context.ex`.

## Known Stubs

None. All operations are fully implemented. `messages/1` filters items correctly. All constructors generate real IDs via `:crypto.strong_rand_bytes/1` and real timestamps via `DateTime.utc_now/0`.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `ChatContext.t()` is ready for use in Phase 02-02 (test coverage)
- Phase 03 (tool system) can use `FunctionCall` and `FunctionCallOutput` structs directly
- Phase 05 (OpenAI provider) can use `ChatContext.messages/1` to extract `ChatMessage` items and convert to OpenAI API format
- `Livekit.Agents.LLM` behaviour's `chat_context :: term()` type annotation can be tightened to `ChatContext.t()` whenever Phase 5 begins

---
*Phase: 02-chat-context*
*Completed: 2026-04-14*

## Self-Check: PASSED

- [x] `lib/livekit/agents/chat_context.ex` exists: FOUND
- [x] Commit `d9dbe13` exists: FOUND (git log confirms)
- [x] `mix compile` exits 0 with no warnings from chat_context.ex
- [x] `mix format --check-formatted lib/livekit/agents/chat_context.ex` exits 0
- [x] `mix credo --strict lib/livekit/agents/chat_context.ex` — 0 issues
- [x] All three Jason.encode! calls succeed in smoke test
- [x] truncate/2 with system message retains system message (verified: total=3, system=1 with 4 non-system messages truncated to 2)

---
phase: 14
plan: 1
subsystem: llm-providers
tags: [anthropic, claude, llm, streaming, tool-calling]
dependency_graph:
  requires: [Livekit.Agents.LLM, Livekit.Agents.ChatContext, Livekit.Agents.Tool]
  provides: [Livekit.Agents.LLM.Anthropic, Livekit.Agents.Tool.ToolSpec.to_anthropic_schema, Livekit.Agents.Tool.ToolContext.to_anthropic_tools]
  affects: [lib/livekit/agents/tool.ex]
tech_stack:
  added: []
  patterns: [behaviour-impl, tesla-http, sse-streaming, mock-mode]
key_files:
  created:
    - lib/livekit/agents/llm/anthropic.ex
    - test/livekit/agents/llm/anthropic_test.exs
  modified:
    - lib/livekit/agents/tool.ex
decisions:
  - Use x-api-key + anthropic-version headers (not Bearer token)
  - Extract system messages to top-level system field (Anthropic API requirement)
  - Merge consecutive same-role messages to satisfy Anthropic's alternating-role constraint
  - Store tool call arguments as JSON string (matching FunctionCall.arguments contract)
  - Default model claude-sonnet-4-20250514 (latest Claude Sonnet at time of implementation)
metrics:
  duration: ~30 minutes
  completed: 2026-04-14
  tasks: 3
  files: 3
---

# Phase 14 Plan 1: Anthropic Claude LLM Provider Summary

Anthropic Claude LLM provider implementing the `@behaviour Livekit.Agents.LLM` contract,
adapted for the Anthropic Messages API (system prompt top-level, tool_use content blocks,
alternating role constraint, x-api-key auth).

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Anthropic provider module | 1a3081c | lib/livekit/agents/llm/anthropic.ex |
| 2 | Anthropic tool schema support | 1a3081c | lib/livekit/agents/tool.ex |
| 3 | Full test suite | 1a3081c | test/livekit/agents/llm/anthropic_test.exs |

## What Was Built

`Livekit.Agents.LLM.Anthropic` — a pure functional LLM provider for the Anthropic Claude
API. Key implementation details:

**Config struct** (`Livekit.Agents.LLM.Anthropic.Config`): `api_key`, `model` (default:
`"claude-sonnet-4-20250514"`), `max_tokens` (default: 1024, required by Anthropic),
`temperature`, `instructions`, `mock`, `base_url`.

**chat/2**: POSTs to `/v1/messages`. Extracts `:system` role ChatMessages into the
top-level `system` field. Converts `FunctionCall` items to `tool_use` content blocks in
assistant messages. Converts `FunctionCallOutput` items to `tool_result` content blocks in
user messages. Merges consecutive same-role messages (Anthropic requires alternating
user/assistant). Returns `{:ok, ChatMessage.t()}` for text or `{:ok, FunctionCall.t()}` for
tool calls.

**stream/2**: Spawns a process that POSTs with `stream: true` and parses
`content_block_delta` SSE events (type `text_delta`) into `{:llm_chunk, %LLMChunk{}}` messages.
Sends terminal `%LLMChunk{type: :done}` on completion.

**Mock mode**: Active when `mock: true` or `api_key` is nil/empty. Returns synthetic
`ChatMessage` for `chat/2` and sends two chunks (`:text`, `:done`) for `stream/2`.

**Tool schema additions** to `lib/livekit/agents/tool.ex`:
- `ToolSpec.to_anthropic_schema/1` — converts to `{name, description, input_schema}` format
- `ToolContext.to_anthropic_tools/1` — returns list of Anthropic tool schema maps

## Test Coverage

28 tests across 6 describe blocks:

- `capabilities/0` — all required keys present, correct values
- `validate_config/1` — mock bypass, nil/empty key rejection, valid key acceptance
- `chat/2 mock mode` — response shape, role, content, no-api-key trigger
- `stream/2 mock mode` — pid returned, text chunk, done chunk
- `chat/2 HTTP via Bypass` — POST path, headers (x-api-key, anthropic-version), text
  response parsing, tool_use response parsing, FunctionCall.arguments JSON validity, 401
  error, system message extraction
- `stream/2 HTTP via Bypass` — pid, text chunks from SSE, terminal done chunk
- `to_anthropic_messages via Bypass` — FunctionCall as tool_use block, FunctionCallOutput
  as tool_result block, tool_context serialized as tools array

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- `lib/livekit/agents/llm/anthropic.ex` exists: FOUND
- `test/livekit/agents/llm/anthropic_test.exs` exists: FOUND
- Commit 1a3081c exists: FOUND
- 28 tests, 0 failures

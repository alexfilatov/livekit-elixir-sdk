---
phase: 10-livebook-showcases
plan: "01"
subsystem: examples
tags: [livebook, tutorial, providers, chat-context, tool-calling]
dependency_graph:
  requires: []
  provides: [LB-01, LB-02, LB-03]
  affects: [examples/livebooks/agents/]
tech_stack:
  added: []
  patterns: [livemd tutorial format, Mix.install with local path, mock provider pattern]
key_files:
  created:
    - examples/livebooks/agents/01_provider_behaviours.livemd
    - examples/livebooks/agents/02_chat_context.livemd
    - examples/livebooks/agents/03_tool_calling.livemd
  modified: []
decisions:
  - "Mix.install path uses Path.join(__DIR__, \"../../..\") to reach project root from examples/livebooks/agents/"
  - "All three livebooks are zero-API-key — all providers are mocked inline"
  - "VAD demo uses process-message passing pattern consistent with behaviour contract"
metrics:
  duration_minutes: 3
  completed_date: "2026-04-14"
  tasks_completed: 3
  tasks_total: 3
  files_created: 3
  files_modified: 0
---

# Phase 10 Plan 01: Livebook Showcases (No-API-Key Trio) Summary

**One-liner:** Three zero-credential Livebook tutorials covering STT/TTS/LLM/VAD provider behaviours, ChatContext conversation management with truncation, and the Tool.run/3 function-calling loop with mock LLMs.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create 01_provider_behaviours.livemd | e7e817c | examples/livebooks/agents/01_provider_behaviours.livemd |
| 2 | Create 02_chat_context.livemd | e7e817c | examples/livebooks/agents/02_chat_context.livemd |
| 3 | Create 03_tool_calling.livemd | e7e817c | examples/livebooks/agents/03_tool_calling.livemd |

## What Was Built

### 01_provider_behaviours.livemd
Covers all four behaviour contracts: STT (batch + streaming), TTS, LLM (batch + streaming), and VAD. Each section shows the minimum required callbacks, a working implementation using Elixir process message passing, and a demonstration of the provider in action. Ends with a capabilities summary loop using `function_exported?/3`.

### 02_chat_context.livemd
Covers ChatContext from empty creation through multi-turn conversations, multi-modal content lists, FunctionCall/FunctionCallOutput pairs, truncation with system-message preservation, orphan FunctionCallOutput detection and removal, context merging, and JSON serialization.

### 03_tool_calling.livemd
Covers ToolSpec definition with JSON Schema parameters, OpenAI function schema generation, ToolContext registry, tool lookup, and the full Tool.run/3 execution loop. Demonstrates the max_tool_steps safety cap with an infinite-looping mock LLM, and error isolation where handler `{:error, reason}` becomes a `FunctionCallOutput(is_error: true)` that the LLM sees as data.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. All livebook cells are fully wired. Providers are intentionally mocked (as per the plan's zero-API-key requirement) but are not placeholders — they demonstrate real behaviour contract usage.

## Threat Flags

No new threat surface introduced. Livebooks are static .livemd files read from the local filesystem. The `InfiniteToolLLM` demo includes the `max_tool_steps: 3` cap explicitly as required by the threat model (T-10-02 mitigation).

## Self-Check: PASSED

Files confirmed present:
- examples/livebooks/agents/01_provider_behaviours.livemd: FOUND
- examples/livebooks/agents/02_chat_context.livemd: FOUND
- examples/livebooks/agents/03_tool_calling.livemd: FOUND

Commit e7e817c: FOUND

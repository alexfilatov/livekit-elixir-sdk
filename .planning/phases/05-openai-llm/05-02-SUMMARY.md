---
phase: 05-openai-llm
plan: "02"
subsystem: agents/llm
tags: [testing, openai, llm, bypass, sse]
dependency_graph:
  requires:
    - 05-01
  provides:
    - TEST-03
  affects:
    - CI test suite
tech_stack:
  added: []
  patterns:
    - Bypass.expect_once for HTTP mocking
    - assert_receive with timeout for async stream assertions
    - Enum.map_join for SSE body construction
key_files:
  created:
    - test/livekit/agents/llm/openai_test.exs
  modified: []
decisions:
  - Bypass async race fixed with assert_receive {:llm_chunk, %LLMChunk{type: :done}} in the stream pid test — ensures the spawned HTTP request completes before Bypass teardown verifies expectations
  - Integration test failures (2) confirmed pre-existing before Plan 05-02; not caused by this plan
metrics:
  duration: 12m
  completed_date: "2026-04-14"
  tasks_completed: 2
  files_changed: 1
---

# Phase 5 Plan 02: OpenAI LLM Tests Summary

One-liner: 23-test ExUnit suite covering OpenAI LLM provider via mock mode and Bypass HTTP with SSE streaming and tool-call serialization.

## What Was Built

Created `test/livekit/agents/llm/openai_test.exs` with 23 tests organized in 6 describe blocks:

| Describe Block | Tests | Coverage |
|---|---|---|
| `capabilities/0` | 3 | Shape, streaming=true, tool_calling=true, vision=false |
| `validate_config/1` | 4 | mock bypass, nil key, empty key, valid key |
| `chat/2 mock mode` | 3 | Returns ok, role :assistant, non-empty content |
| `stream/2 mock mode` | 3 | Returns pid, receives text chunk, receives :done chunk |
| `chat/2 HTTP via Bypass` | 5 | POST route, text response, content match, tool call, 401 error |
| `stream/2 HTTP via Bypass` | 3 | Returns pid, receives SSE text chunks, receives :done |
| `to_openai_messages via Bypass` | 2 | FunctionCall → assistant+tool_calls, FunctionCallOutput → role:tool |

**Total: 23 tests, 0 failures.**

## Test Infrastructure Patterns

- **Bypass pattern**: `Bypass.open()` in setup, `config_for(bypass)` helper overrides `base_url` to `http://localhost:#{bypass.port}`, `Bypass.expect_once/4` verifies route was hit exactly once.
- **SSE body helper**: `sse_body/1` uses `Enum.map_join` to produce `data: {...}\n\n` lines with a terminal `data: [DONE]\n\n`.
- **Async stream fix**: Stream tests use `assert_receive {:llm_chunk, %LLMChunk{type: :done}}, 2000` to let the spawned HTTP process complete before Bypass teardown — prevents "No HTTP request arrived" failures.
- **Request inspection**: `Plug.Conn.read_body/1` inside the Bypass handler captures the outgoing JSON body for serialization assertions.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Bypass teardown race in stream/2 pid test**
- **Found during:** Task 1 first test run
- **Issue:** `stream/2` spawns a process that makes the HTTP request asynchronously. The test returned before the spawned process hit the Bypass server, causing "No HTTP request arrived at Bypass" on teardown.
- **Fix:** Added `assert_receive {:llm_chunk, %LLMChunk{type: :done}}, 2000` after asserting pid — this blocks the test until the stream completes, satisfying Bypass's expectation.
- **Files modified:** `test/livekit/agents/llm/openai_test.exs`
- **Commit:** 0e56512

**2. [Rule 2 - Credo] Fixed alias ordering and Enum.map_join**
- **Found during:** Task 1 credo run
- **Issue:** Aliases not in alphabetical order; `Enum.map/2 |> Enum.join/2` flagged as refactoring opportunity.
- **Fix:** Reordered aliases alphabetically; replaced with `Enum.map_join/2`.
- **Files modified:** `test/livekit/agents/llm/openai_test.exs`
- **Commit:** 0e56512

## Pre-existing Failures (Not Caused by This Plan)

2 tests in `test/livekit/agents/integration_test.exs` fail both before and after this plan:
1. `test Error Handling handles missing API keys gracefully` — calls `Deepgram.start_link/1` which doesn't exist (Deepgram is pure functional, not GenServer)
2. `test Voice Agent Integration agent session lifecycle` — `refute status.room_connected` fails because mock auto-connects

These are out-of-scope pre-existing issues logged for future work.

## Known Stubs

None. All tests exercise real code paths.

## Threat Flags

None. Test fixtures use hardcoded `"sk-test"` strings — no real credentials.

## Self-Check: PASSED

- [x] `test/livekit/agents/llm/openai_test.exs` exists and has 376 lines
- [x] Commit `0e56512` exists in git log
- [x] `mix test test/livekit/agents/llm/openai_test.exs` — 23 tests, 0 failures
- [x] `mix credo --strict test/livekit/agents/llm/openai_test.exs` — no issues
- [x] `mix compile --warnings-as-errors` — clean
- [x] Full `mix test` — 316 tests pass (2 pre-existing integration failures unrelated to this plan)

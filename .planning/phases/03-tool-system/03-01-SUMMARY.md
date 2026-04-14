---
phase: 03-tool-system
plan: 01
subsystem: api
tags: [tool-calling, openai, function-calling, llm, chat-context]

requires:
  - phase: 02-chat-context
    provides: FunctionCall and FunctionCallOutput structs, ChatContext.add/2, ChatContext.new_function_call_output/4

provides:
  - ToolSpec struct with OpenAI function-calling JSON schema generation
  - ToolContext registry with O(1) lookup and to_openai_tools/1
  - ToolError defexception for handler failure wrapping
  - Tool.run/3 execution loop driving LLM tool calling with max_tool_steps cap

affects: [05-openai-llm, 07-voice-pipeline]

tech-stack:
  added: []
  patterns:
    - "Nested module co-location: ToolSpec, ToolContext, ToolError all in tool.ex under Livekit.Agents.Tool"
    - "try/rescue in execute_call/2 wraps all handler exceptions into FunctionCallOutput(is_error: true)"
    - "Private helper extraction to satisfy Credo max nesting depth (execute_all_calls/3)"

key-files:
  created:
    - lib/livekit/agents/tool.ex
  modified: []

key-decisions:
  - "rescue err in [ToolError] form used (not struct pattern) because Elixir rescue does not allow struct pattern match syntax"
  - "execute_all_calls/3 extracted from do_run/6 to satisfy Credo max nesting depth of 2"
  - "Pre-existing warnings in other files (stt/deepgram.ex, tts/openai.ex, pipeline.ex, agent_session.ex) are out of scope — not touched"

patterns-established:
  - "Tool handler contract: (map() -> {:ok, String.t()} | {:error, String.t()})"
  - "All tool exceptions caught and surfaced as FunctionCallOutput(is_error: true) — never crash the caller"
  - "max_tool_steps safety cap enforced before executing calls at each step"

requirements-completed: [TOOL-01, TOOL-02, TOOL-03, TOOL-04, TOOL-05]

duration: 2min
completed: 2026-04-14
---

# Phase 3 Plan 01: Tool System Summary

**ToolSpec/ToolContext/ToolError structs plus Tool.run/3 execution loop for provider-agnostic LLM tool calling with max_tool_steps DoS protection**

## Performance

- **Duration:** 2 min
- **Started:** 2026-04-14T10:19:39Z
- **Completed:** 2026-04-14T10:21:59Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- `ToolSpec` struct with `new/1` constructor and `to_openai_schema/1` producing OpenAI function-calling JSON format
- `ToolContext` registry with `new/1`, `lookup/2` (O(1) by name), and `to_openai_tools/1` for batch schema generation
- `ToolError` defexception with `call_id`, `tool_name`, `reason` fields for structured error wrapping
- `Tool.run/3` execution loop that calls LLM, detects new `FunctionCall` items in context, executes handlers via `ToolContext.lookup`, feeds `FunctionCallOutput` results back, and repeats up to `max_tool_steps` (default 10)
- All handler exceptions and `{:error, reason}` returns are caught and converted to `FunctionCallOutput(is_error: true)` — the caller process never crashes

## Task Commits

Each task was committed atomically:

1. **Task 1 + Task 2: ToolSpec, ToolContext, ToolError, and Tool.run/3** - `c678ada` (feat)

**Plan metadata:** (to be added after docs commit)

## Files Created/Modified

- `lib/livekit/agents/tool.ex` — ToolSpec, ToolContext, ToolError nested modules plus Tool.run/3 execution loop (359 lines)

## Decisions Made

- Used `rescue err in [ToolError]` form (module-list syntax) because Elixir rescue clauses do not support struct pattern-match syntax (`%ToolError{} = err`)
- Extracted `execute_all_calls/3` private helper from the `do_run/6` `cond` branch to satisfy Credo strict max nesting depth of 2
- Pre-existing warnings in `stt/deepgram.ex`, `tts/openai.ex`, `pipeline.ex`, and `agent_session.ex` are out of scope per deviation boundary rules — those files were not touched

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed invalid rescue clause syntax**
- **Found during:** Task 1/2 (compile verification)
- **Issue:** Plan used `%ToolError{} = err ->` in rescue clause; Elixir does not allow struct pattern-match syntax in rescue
- **Fix:** Changed to `err in [ToolError] ->` (module-list form that Elixir supports)
- **Files modified:** lib/livekit/agents/tool.ex
- **Verification:** `mix compile` passes with no errors in tool.ex
- **Committed in:** c678ada (task commit)

**2. [Rule 1 - Refactor] Extracted execute_all_calls/3 for Credo nesting**
- **Found during:** Task 2 (Credo verification)
- **Issue:** Inline `Enum.reduce` lambda inside `cond` inside `case` exceeded Credo's max nesting depth of 2
- **Fix:** Extracted to private `execute_all_calls/3` helper, called from `do_run/6`
- **Files modified:** lib/livekit/agents/tool.ex
- **Verification:** `mix credo --strict lib/livekit/agents/tool.ex` reports no issues
- **Committed in:** c678ada (task commit)

---

**Total deviations:** 2 auto-fixed (1 compile bug fix, 1 refactor for Credo compliance)
**Impact on plan:** Both fixes are syntactic/structural — zero behavior change. Plan intent executed exactly.

## Issues Encountered

- `mix compile --warnings-as-errors` fails due to pre-existing warnings in unrelated files (`stt/deepgram.ex`, `tts/openai.ex`, `pipeline.ex`, `agent_session.ex`). These are logged to deferred-items and out of scope for this plan.

## Known Stubs

None — all public functions are fully implemented. No placeholder values or TODO stubs.

## Threat Flags

No new network endpoints, auth paths, file access patterns, or schema changes introduced. All threat mitigations from the plan's threat model are implemented:

| Threat | Mitigation |
|--------|-----------|
| T-03-01 Handler elevation | All handler calls wrapped in try/rescue in execute_call/2 |
| T-03-02 Infinite loop DoS | max_tool_steps cap enforced in do_run/6 before executing calls |
| T-03-03 Malformed JSON from LLM | Jason.decode!/1 raises caught by try/rescue -> is_error: true output |

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Tool system is complete and ready for Phase 5 (OpenAI LLM provider) to integrate by passing `tool_context:` to `Tool.run/3`
- Phase 7 (Voice Pipeline) can use `Tool.run/3` as the LLM execution loop entry point
- `ToolContext.to_openai_tools/1` is the bridge to OpenAI's `tools:` parameter

---
*Phase: 03-tool-system*
*Completed: 2026-04-14*

# Phase 3: Tool System - Context

**Gathered:** 2026-04-14
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase)

<domain>
## Phase Boundary

Tool specification structs, JSON schema generation for OpenAI function calling format, and an execution loop that invokes tool handlers and feeds results back to the LLM. Configurable max_tool_steps to prevent infinite loops. ToolError handling that surfaces failures back to LLM.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — infrastructure phase with clear success criteria.

Key constraints from project context:
- Tool spec struct needs: name, description, parameter schema (JSON Schema format)
- Execution loop: LLM returns FunctionCall -> look up handler -> execute -> wrap result in FunctionCallOutput -> feed back to LLM -> repeat
- max_tool_steps config to prevent infinite loops (default: 10)
- ToolError exception that gets caught and converted to FunctionCallOutput with is_error: true
- JSON schema generation from tool definitions (for OpenAI function calling format)
- Use ChatContext structs from Phase 2 (FunctionCall, FunctionCallOutput)
- Follow existing codebase conventions

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Livekit.Agents.ChatContext.FunctionCall` — tool call request struct (Phase 2)
- `Livekit.Agents.ChatContext.FunctionCallOutput` — tool result struct (Phase 2)
- `Livekit.Agents.LLM` behaviour — defines chat/2 callback that returns responses potentially containing tool calls
- `Livekit.Agents.LLM.LLMChunk` — streaming chunk with type: :tool_call

### Established Patterns
- Nested module structs with @type and defstruct
- {:ok, result} / {:error, reason} return tuples

### Integration Points
- Tool system will be used by the voice pipeline (Phase 7) and OpenAI LLM provider (Phase 5)
- LLM providers convert tool definitions to their provider-specific format (OpenAI function calling JSON)

</code_context>

<specifics>
## Specific Ideas

- Mirror Python agents' @function_tool pattern but use Elixir idioms
- Tool handlers are simple functions: (args_map) -> {:ok, result} | {:error, reason}
- JSON schema should match OpenAI's function calling schema format

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 03-tool-system*
*Context gathered: 2026-04-14*

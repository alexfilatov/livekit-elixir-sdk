# Phase 5: OpenAI LLM - Context

**Gathered:** 2026-04-14
**Status:** Ready for planning
**Mode:** Auto-generated (provider implementation)

<domain>
## Phase Boundary

Real OpenAI LLM provider implementing the LLM behaviour. HTTP POST to /v1/chat/completions with SSE streaming support. Tool/function calling via ChatContext FunctionCall structs. Token-aware conversation truncation. Mock mode for testing.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
Key constraints:
- Refactor existing `lib/livekit/agents/llm/openai.ex` to implement `@behaviour Livekit.Agents.LLM`
- Real HTTP POST to `https://api.openai.com/v1/chat/completions`
- SSE streaming: parse `data: {...}` lines for real-time token delivery
- Convert ChatContext messages to OpenAI API format (role/content/tool_calls/tool_call_id)
- Function/tool calling: convert ToolSpec to OpenAI function schema, parse tool_calls from response
- Token-aware truncation: estimate tokens, truncate ChatContext to fit model limit
- Mock mode when config.mock: true or no api_key
- Use Tesla for HTTP (already in deps)
- Auth via `Authorization: Bearer <api_key>` header

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/livekit/agents/llm/openai.ex` — existing mock with correct config struct
- `lib/livekit/agents/llm.ex` — LLM behaviour with LLMChunk struct (Phase 1)
- `lib/livekit/agents/chat_context.ex` — ChatContext, ChatMessage, FunctionCall, FunctionCallOutput (Phase 2)
- `lib/livekit/agents/tool.ex` — ToolSpec, ToolContext with to_openai_tools/1 (Phase 3)

### Integration Points
- Tool.run/3 calls LLM.chat/2 in the execution loop
- Pipeline (Phase 7) will use this provider
- ToolContext.to_openai_tools/1 generates the tools parameter

</code_context>

<specifics>
## Specific Ideas

No specific requirements — follow OpenAI API documentation and existing patterns.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>

---

*Phase: 05-openai-llm*
*Context gathered: 2026-04-14*

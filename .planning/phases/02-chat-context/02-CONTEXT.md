# Phase 2: Chat Context - Context

**Gathered:** 2026-04-14
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase)

<domain>
## Phase Boundary

Typed structs for conversation messages (ChatMessage, FunctionCall, FunctionCallOutput) and a ChatContext module with add, truncate, merge, copy operations. Truncation must preserve system messages. Structs must round-trip through Jason encode/decode.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — infrastructure phase with clear success criteria. Use ROADMAP phase goal, success criteria, and codebase conventions to guide decisions.

Key constraints from prior phases and project context:
- Follow existing codebase conventions (nested Config structs, {:ok, result} / {:error, reason} tuples)
- ChatMessage roles: system, user, assistant, tool (matching Python agents ChatMessage.role)
- ChatContext should be a struct with an ordered list of ChatItem entries
- FunctionCall needs: call_id, name, arguments fields
- FunctionCallOutput needs: call_id, result, error flag
- Truncation must preserve system messages regardless of token budget
- Support multi-modal content (plain text strings and structured maps)
- Implement Jason.Encoder for all structs to ensure round-trip encoding

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase 1 behaviours define `LLMChunk` struct at `lib/livekit/agents/llm.ex` — LLM behaviour uses `term()` for chat_context, will be updated to use `ChatContext.t()` after this phase
- Existing conversation context in `voice_agent.ex` uses simple `{type, content, timestamp}` tuples — this phase replaces that with proper structs

### Established Patterns
- Nested module structs with `@type t :: %__MODULE__{}` and `defstruct`
- `@moduledoc` required on all public modules
- `@spec` on all public functions

### Integration Points
- `Livekit.Agents.LLM` behaviour's `chat/2` callback accepts `term()` for chat_context — will be typed to `ChatContext.t()` after this phase
- `VoiceAgent` maintains `conversation_context` list — will use `ChatContext` after this phase
- OpenAI LLM provider (Phase 5) will convert ChatContext to OpenAI API message format

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches following Python agents ChatContext patterns.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 02-chat-context*
*Context gathered: 2026-04-14*

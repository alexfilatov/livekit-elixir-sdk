# Phase 8: State & Events - Context

**Gathered:** 2026-04-14
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase)

<domain>
## Phase Boundary

User and agent state machines with typed event structs, :telemetry metrics integration, and Registry-based pub/sub for event consumers. User states: listening/speaking/away. Agent states: initializing/listening/thinking/speaking.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
Key constraints:
- User state machine: listening -> speaking (on VAD speech) -> away (on configurable timeout, default 30s)
- Agent state machine: initializing -> listening (ready) -> thinking (LLM processing) -> speaking (TTS playing)
- Both implemented as GenServer or GenStateMachine
- Typed event structs for all state changes (UserStateChanged, AgentStateChanged, SpeechCreated, ErrorEvent, etc.)
- :telemetry events for TTFT (time to first token), end-to-end latency, token counts
- Registry-based pub/sub: processes subscribe via Registry, receive events without polling
- Events should be pattern-matchable structs
- Pipeline already emits :telemetry events — this phase adds the state machine layer and event pub/sub

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- Pipeline already emits :telemetry events (stt_complete, llm_first_token, tts_start)
- EnergyVAD classifies speech/silence
- TurnDetector sends turn_start/turn_end

### Integration Points
- Pipeline state transitions drive agent state machine (listening -> thinking -> speaking)
- VAD/TurnDetector events drive user state machine (listening -> speaking)
- VoiceAgent will own both state machines
- Events published via Registry for external consumers

</code_context>

<specifics>
## Specific Ideas

No specific requirements — follow standard Elixir patterns.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>

---

*Phase: 08-state-events*
*Context gathered: 2026-04-14*

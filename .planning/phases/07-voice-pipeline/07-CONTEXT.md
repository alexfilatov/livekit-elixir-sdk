# Phase 7: Voice Pipeline - Context

**Gathered:** 2026-04-14
**Status:** Ready for planning
**Mode:** Auto-generated (core feature with clear success criteria)

<domain>
## Phase Boundary

Streaming STT -> LLM -> TTS pipeline with energy-based VAD, configurable turn detection with fixed endpointing, and basic interruption handling. Any conforming STT/LLM/TTS provider can be swapped in. Emits :telemetry events at each stage. This replaces the existing mock Pipeline module.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
Key constraints:
- Refactor existing `lib/livekit/agents/pipeline.ex` to use real provider behaviours
- Energy-based VAD: calculate RMS of audio frames, compare against configurable threshold
- Turn detection: after VAD detects end of speech, wait configurable silence duration (default 0.5s) before triggering LLM
- Interruption: if new speech detected while TTS is playing, cancel current synthesis and restart cycle
- Pipeline should be a GenServer that accepts audio frames and orchestrates the flow
- Use provider behaviours — any conforming STT/LLM/TTS module works
- Emit :telemetry events: [:livekit, :agents, :pipeline, :stt_complete], [:livekit, :agents, :pipeline, :llm_first_token], [:livekit, :agents, :pipeline, :tts_start]
- Backpressure: don't block audio frame producer while processing
- The pipeline owns the conversation ChatContext and updates it as messages flow through
- Integration test with mock providers verifying full STT->LLM->TTS flow

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/livekit/agents/pipeline.ex` — existing mock pipeline (will be rewritten)
- `lib/livekit/agents/stt.ex` — STT behaviour
- `lib/livekit/agents/llm.ex` — LLM behaviour
- `lib/livekit/agents/tts.ex` — TTS behaviour
- `lib/livekit/agents/vad.ex` — VAD behaviour
- `lib/livekit/agents/chat_context.ex` — ChatContext for conversation state
- `lib/livekit/agents/tool.ex` — Tool system for function calling
- `lib/livekit/agents/audio_frame.ex` — AudioFrame with RMS silence detection

### Established Patterns
- GenServer with nested Config/State structs
- Provider injection via {module, config} tuples
- :telemetry for instrumentation (standard Elixir pattern)

### Integration Points
- VoiceAgent will own the Pipeline GenServer
- AgentSession feeds audio frames into pipeline
- Pipeline outputs audio frames back to AgentSession for room publishing

</code_context>

<specifics>
## Specific Ideas

- Keep it simple for v1 — no GenStage, just a GenServer with async processing via Task
- VAD can use AudioFrame.is_silence?/2 which already does RMS calculation
- Turn detection is a simple timer: reset on speech, trigger on timeout

</specifics>

<deferred>
## Deferred Ideas

- GenStage backpressure (future optimization)
- Dynamic endpointing based on speech patterns
- Adaptive interruption detection (ML-based)

</deferred>

---

*Phase: 07-voice-pipeline*
*Context gathered: 2026-04-14*

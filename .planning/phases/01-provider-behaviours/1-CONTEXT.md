# Phase 1: Provider Behaviours - Context

**Gathered:** 2026-04-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Define Elixir behaviour modules for STT, TTS, LLM, and VAD provider types. These are the contracts that all provider implementations must conform to. Any module implementing a behaviour can be plugged into the voice pipeline. This phase does NOT implement any real providers — only the contracts.

</domain>

<decisions>
## Implementation Decisions

### Callback Design
- **D-01:** STT behaviour defines `transcribe/2` (batch: audio binary + opts -> transcript) and `stream/1` (returns a streaming process ref that sends `{:speech_event, event}` messages)
- **D-02:** TTS behaviour defines `synthesize/2` (batch: text + opts -> audio binary) and `stream/1` (returns streaming process that accepts text chunks and emits audio frames)
- **D-03:** LLM behaviour defines `chat/2` (chat_context + opts -> chat_message) and `stream/2` (chat_context + opts -> streaming process emitting text chunks)
- **D-04:** VAD behaviour defines `stream/1` (returns process that accepts audio frames and emits `{:vad_event, event}` messages for speech start/end)
- **D-05:** Follow the Python agents pattern: batch methods are synchronous request/response, stream methods return a process that emits events asynchronously

### Capability Introspection
- **D-06:** Each behaviour requires a `capabilities/0` callback returning `%{atom => boolean | term}`
- **D-07:** STT capabilities: `streaming`, `interim_results`, `diarization`, `languages`
- **D-08:** TTS capabilities: `streaming`, `voices`, `audio_formats`, `word_timing`
- **D-09:** LLM capabilities: `streaming`, `tool_calling`, `vision`, `max_context_tokens`
- **D-10:** VAD capabilities: `realtime`, `speech_probability`

### Error Handling Contract
- **D-11:** Batch callbacks return `{:ok, result}` or `{:error, reason}` — follows existing codebase convention
- **D-12:** Streaming processes send `{:error, reason}` message to subscriber on failure
- **D-13:** Define common error types: `:api_error`, `:timeout`, `:invalid_config`, `:rate_limited`

### Configuration Pattern
- **D-14:** Keep existing `{module, config_map}` tuple pattern from VoiceAgent.Config — providers receive config as a map in their init
- **D-15:** Each behaviour optionally defines `validate_config/1` callback (default impl returns `:ok`)
- **D-16:** Each behaviour defines `@type config :: map()` for documentation

### Event/Message Types
- **D-17:** Define `SpeechEvent` struct for STT: `%{type: :start | :interim | :final | :end, text: String.t(), confidence: float(), language: String.t()}`
- **D-18:** Define `VADEvent` struct: `%{type: :speech_start | :speech_end | :inference, probability: float(), frames: [AudioFrame.t()]}`
- **D-19:** Define `LLMChunk` struct for streaming: `%{type: :text | :tool_call | :done, content: term()}`

### Claude's Discretion
- Exact typespec syntax and optional callback organization
- Whether to use `@optional_callbacks` for streaming or make all callbacks required
- Helper macros or `__using__` hooks for common boilerplate

</decisions>

<specifics>
## Specific Ideas

- Mirror the Python agents' interface patterns (STT.stream() -> RecognizeStream, TTS.stream() -> SynthesizeStream, LLM.chat() -> LLMStream) but use Elixir idioms (GenServer processes, message passing)
- Behaviours should be minimal — don't over-specify. Providers can extend beyond the contract
- Include `@doc` examples in each behaviour showing how a conforming module would look

</specifics>

<canonical_refs>
## Canonical References

### Python Agents Reference (upstream)
- No local specs — the Python LiveKit Agents framework at github.com/livekit/agents is the reference implementation
- Key interfaces: `stt/stt.py` (RecognizeStream), `tts/tts.py` (SynthesizeStream), `llm/llm.py` (LLMStream), `vad.py` (VADStream)

### Existing Codebase
- `.planning/codebase/ARCHITECTURE.md` — Current module hierarchy and GenServer patterns
- `.planning/codebase/CONVENTIONS.md` — Elixir coding conventions, behaviour patterns, error handling
- `lib/livekit/agents/audio_frame.ex` — AudioFrame struct that behaviours will reference
- `lib/livekit/agents/stt/deepgram.ex` — Existing mock STT (will be refactored to implement behaviour)
- `lib/livekit/agents/llm/openai.ex` — Existing mock LLM (will be refactored to implement behaviour)
- `lib/livekit/agents/tts/openai.ex` — Existing mock TTS (will be refactored to implement behaviour)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AudioFrame` struct at `lib/livekit/agents/audio_frame.ex` — behaviours will reference this type
- Existing provider modules have GenServer patterns and config structs that can inform the behaviour design

### Established Patterns
- GenServer with nested `Config` and `State` structs — providers follow this
- `{module, config_map}` tuple for provider injection in `VoiceAgent.Config`
- `@impl true` on all callbacks, `@spec` on all public functions
- `{:ok, result}` / `{:error, reason}` return convention

### Integration Points
- `VoiceAgent.Config` already uses `{module, config}` tuples for `stt`, `llm`, `tts`
- `Pipeline` will call behaviour callbacks to process audio/text
- Existing provider modules will add `@behaviour` declarations after behaviours are defined

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-provider-behaviours*
*Context gathered: 2026-04-14*

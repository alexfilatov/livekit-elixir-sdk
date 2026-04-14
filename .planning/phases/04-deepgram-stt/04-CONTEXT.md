# Phase 4: Deepgram STT - Context

**Gathered:** 2026-04-14
**Status:** Ready for planning
**Mode:** Auto-generated (provider implementation with clear API contracts)

<domain>
## Phase Boundary

Real Deepgram speech-to-text provider implementing the STT behaviour. Batch HTTP transcription via POST to /v1/listen and streaming WebSocket transcription. Supports interim results, configurable audio buffering, and mock mode for testing without API keys.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
Implementation follows the STT behaviour contract from Phase 1 and existing Deepgram mock patterns. Key constraints:

- Refactor existing `lib/livekit/agents/stt/deepgram.ex` to implement `@behaviour Livekit.Agents.STT`
- Real HTTP POST to `https://api.deepgram.com/v1/listen` for batch transcription
- Real WebSocket connection to `wss://api.deepgram.com/v1/listen` for streaming
- Auth via `Token <api_key>` header
- Parse Deepgram JSON responses into SpeechEvent structs
- Support interim_results in streaming mode
- Audio buffering: accumulate configurable minimum duration before sending
- Mock mode: when config has `mock: true` or no api_key, return synthetic results (for CI)
- Keep existing config struct fields (model: "nova-2", language: "en-US", etc.)
- Use Tesla for HTTP, Gun for WebSocket (both already in deps)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/livekit/agents/stt/deepgram.ex` — existing mock implementation with correct config struct
- `lib/livekit/agents/stt.ex` — STT behaviour with SpeechEvent struct (Phase 1)
- `lib/livekit/agents/audio_frame.ex` — AudioFrame type for audio input

### Established Patterns
- GenServer with nested Config/State structs
- Tesla HTTP client with Hackney adapter
- `{:ok, result}` / `{:error, reason}` returns

### Integration Points
- Must implement `Livekit.Agents.STT` behaviour callbacks
- Pipeline (Phase 7) will call transcribe/2 and stream/1
- VoiceAgent config uses `{Livekit.Agents.STT.Deepgram, config_map}` tuple

</code_context>

<specifics>
## Specific Ideas

No specific requirements — follow Deepgram API documentation and existing mock patterns.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>

---

*Phase: 04-deepgram-stt*
*Context gathered: 2026-04-14*

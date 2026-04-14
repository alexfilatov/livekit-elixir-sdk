# Phase 6: OpenAI TTS - Context

**Gathered:** 2026-04-14
**Status:** Ready for planning
**Mode:** Auto-generated (provider implementation)

<domain>
## Phase Boundary

Real OpenAI TTS provider implementing the TTS behaviour. HTTP POST to /v1/audio/speech with configurable voices (alloy, echo, fable, onyx, nova, shimmer), audio formats (PCM, MP3, Opus, AAC, FLAC), response caching with TTL and size limits, and mock mode for testing.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
Key constraints:
- Refactor existing `lib/livekit/agents/tts/openai.ex` to implement `@behaviour Livekit.Agents.TTS`
- Real HTTP POST to `https://api.openai.com/v1/audio/speech`
- Auth via `Authorization: Bearer <api_key>` header
- Support all 6 voices and 5 audio formats
- Response caching: SHA256 key from (model+voice+speed+text), configurable TTL and max cache size
- Convert audio response to AudioFrame struct
- Mock mode when config.mock: true or no api_key (generate sine wave like existing mock)
- Use Tesla for HTTP
- No Tesla.Middleware.Logger (avoid leaking Bearer token)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/livekit/agents/tts/openai.ex` — existing mock with correct config struct and sine wave generation
- `lib/livekit/agents/tts.ex` — TTS behaviour (Phase 1)
- `lib/livekit/agents/audio_frame.ex` — AudioFrame for output

### Integration Points
- Pipeline (Phase 7) calls synthesize/2
- VoiceAgent config uses `{Livekit.Agents.TTS.OpenAI, config_map}` tuple

</code_context>

<specifics>
## Specific Ideas

No specific requirements — follow OpenAI API documentation.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>

---

*Phase: 06-openai-tts*
*Context gathered: 2026-04-14*

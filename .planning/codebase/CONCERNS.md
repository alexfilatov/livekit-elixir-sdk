# LiveKit Elixir SDK - Technical Concerns

## Critical: Mock Implementations (Production Blockers)

Every major agent subsystem uses mock implementations that must be replaced.

### STT - Deepgram (`lib/livekit/agents/stt/deepgram.ex`)
- `mock_transcribe()` returns hardcoded text based on audio size
- WebSocket streaming uses `:mock_websocket` atom instead of real connection
- `send_audio_to_websocket()` simulates with `spawn()` and hardcoded delays
- **Needs:** Real WebSocket to `wss://api.deepgram.com/v1/listen`, proper protocol handling

### LLM - OpenAI (`lib/livekit/agents/llm/openai.ex`)
- `mock_llm_response()` does simple string matching ("hello" -> canned response)
- Request body constructed but never sent
- Token estimation is rough (`String.length / 4`)
- **Needs:** Real HTTP POST to `/v1/chat/completions`, streaming SSE, proper tokenization

### TTS - OpenAI (`lib/livekit/agents/tts/openai.ex`)
- `mock_tts_synthesis()` generates sine waves at different frequencies per voice
- No actual voice quality, prosody, or natural speech
- **Needs:** Real HTTP POST to `/v1/audio/speech`, audio format handling

### Pipeline (`lib/livekit/agents/pipeline.ex`)
- Node init silently creates `:mock` state on failure (masks real errors)
- Fallback mock implementations for all three stages
- **Needs:** Strict error handling, real provider initialization

### Agent Session (`lib/livekit/agents/agent_session.ex`)
- Room connection entirely simulated (sets `room_connected: true` without network)
- `simulate_room_events()` spawns infinite loop generating fake participant events
- Message sending just logs and returns `:ok`
- **Needs:** Real WebRTC/room connection (biggest gap)

### Worker (`lib/livekit/agents/worker.ex`)
- Server registration mocked — sets `connection: :mock_connection`
- `send_heartbeat()` just logs
- **Needs:** WebSocket to LiveKit server, protocol-compliant job handling

## Security Concerns

### API Key Handling
- Keys passed directly in HTTP headers via Tesla middleware
- Keys stored in plain text in GenServer state
- Tesla.Middleware.Logger could expose keys if debug enabled
- **Files:** `stt/deepgram.ex`, `llm/openai.ex`, `tts/openai.ex`
- **Fix:** Environment variables, secret management, credential sanitization

### Token Generation (`lib/livekit/agents/job_context.ex`)
- Hardcoded 1-hour TTL for room tokens
- `can_publish_data: true` granted by default
- `sanitize_for_logging()` masks to first/last 2 chars (weak for short keys)

## Memory & Performance

### Unbounded Growth
| Issue | File | Description |
|-------|------|-------------|
| Conversation history | `llm/openai.ex` | List grows indefinitely, no pruning |
| Audio buffer | `stt/deepgram.ex` | Concatenated without size limit |
| TTS cache | `tts/openai.ex` | No eviction policy, no TTL, no size limit |
| Process leak | `agent_session.ex` | `simulate_room_events()` infinite `spawn_link` recursion |

### Audio Processing (`lib/livekit/agents/audio_frame.ex`)
- `simple_resample()` uses basic linear interpolation (audible artifacts)
- Stereo split only works for PCM16
- RMS silence detection only for PCM16 (returns 0.0 for other formats)

## Error Handling Gaps
- Generic `rescue` clauses catching all errors without specific recovery
- Hardcoded timeouts (5000ms GenServer calls) without backpressure
- No circuit breaker pattern for external API calls
- No retry logic with exponential backoff

## Missing Production Features
- No OpenTelemetry / distributed tracing
- No metrics beyond basic counters in state
- No circuit breaker for API calls
- No graceful degradation when services unavailable
- No load testing infrastructure

## Priority Order

1. **Critical:** Replace mocks with real API calls (STT, LLM, TTS, room connection, worker registration)
2. **High:** Fix memory leaks, add bounded buffers/caches, secure API keys
3. **Medium:** Proper error handling, audio resampling, observability
4. **Low:** OpenTelemetry, distributed tracing, ML-based VAD

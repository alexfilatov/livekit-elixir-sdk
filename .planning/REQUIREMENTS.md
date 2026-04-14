# Requirements: LiveKit Elixir Agents Framework

**Defined:** 2026-04-14
**Core Value:** A developer can build and deploy a working voice AI agent using only Elixir with real provider integrations, not mocks.

## v1 Requirements

### Provider Behaviours

- [x] **BEHV-01**: Define `Livekit.Agents.STT` behaviour with callbacks for streaming and batch transcription
- [x] **BEHV-02**: Define `Livekit.Agents.TTS` behaviour with callbacks for streaming and batch synthesis
- [x] **BEHV-03**: Define `Livekit.Agents.LLM` behaviour with callbacks for chat completion and streaming
- [x] **BEHV-04**: Define `Livekit.Agents.VAD` behaviour with callbacks for voice activity detection
- [x] **BEHV-05**: Each behaviour defines capability introspection (what features provider supports)

### Chat Context

- [x] **CHAT-01**: Define `ChatMessage` struct with id, role (system/user/assistant/tool), content, timestamp
- [x] **CHAT-02**: Define `FunctionCall` struct with call_id, name, arguments
- [x] **CHAT-03**: Define `FunctionCallOutput` struct with call_id, result, error flag
- [x] **CHAT-04**: Define `ChatContext` module with add, truncate, merge, copy operations
- [x] **CHAT-05**: ChatContext preserves system messages during truncation
- [x] **CHAT-06**: ChatContext supports multi-modal content types (text, structured)

### Tool System

- [ ] **TOOL-01**: Define tool specification struct with name, description, parameter schema
- [ ] **TOOL-02**: Tool execution loop: LLM generates call -> execute -> feed result back -> repeat
- [ ] **TOOL-03**: Configurable max_tool_steps to prevent infinite loops
- [ ] **TOOL-04**: ToolError handling that surfaces failures back to LLM
- [ ] **TOOL-05**: JSON schema generation from tool definitions

### Deepgram STT Provider

- [ ] **DSTT-01**: Real HTTP POST to Deepgram `/v1/listen` for batch transcription
- [ ] **DSTT-02**: Real WebSocket connection to Deepgram for streaming transcription
- [ ] **DSTT-03**: Support interim results and final transcripts in streaming mode
- [ ] **DSTT-04**: Audio buffering with configurable minimum duration before send
- [ ] **DSTT-05**: Implements `Livekit.Agents.STT` behaviour
- [ ] **DSTT-06**: Mock mode for testing without API key

### OpenAI LLM Provider

- [ ] **OLLM-01**: Real HTTP POST to OpenAI `/v1/chat/completions`
- [ ] **OLLM-02**: SSE streaming response parsing for real-time text generation
- [ ] **OLLM-03**: Function/tool calling support with schema translation
- [ ] **OLLM-04**: Conversation history management with token-aware truncation
- [ ] **OLLM-05**: Implements `Livekit.Agents.LLM` behaviour
- [ ] **OLLM-06**: Mock mode for testing without API key

### OpenAI TTS Provider

- [ ] **OTTS-01**: Real HTTP POST to OpenAI `/v1/audio/speech`
- [ ] **OTTS-02**: Support all voices (alloy, echo, fable, onyx, nova, shimmer)
- [ ] **OTTS-03**: Support audio formats (PCM, MP3, Opus, AAC, FLAC)
- [ ] **OTTS-04**: Response caching with TTL and size limits
- [ ] **OTTS-05**: Implements `Livekit.Agents.TTS` behaviour
- [ ] **OTTS-06**: Mock mode for testing without API key

### Voice Pipeline

- [ ] **PIPE-01**: Streaming STT -> LLM -> TTS pipeline with backpressure handling
- [ ] **PIPE-02**: Energy-based VAD implementation for speech/silence detection
- [ ] **PIPE-03**: Turn detection with configurable fixed endpointing (min/max silence duration)
- [ ] **PIPE-04**: Basic interruption handling (cancel current TTS on new user speech)
- [ ] **PIPE-05**: Pipeline uses provider behaviours (any conforming module works)
- [ ] **PIPE-06**: Pipeline emits :telemetry events for each processing stage

### State & Events

- [ ] **EVNT-01**: User state machine: listening -> speaking -> away (with configurable timeout)
- [ ] **EVNT-02**: Agent state machine: initializing -> listening -> thinking -> speaking
- [ ] **EVNT-03**: Typed event structs for all state changes and conversation events
- [ ] **EVNT-04**: :telemetry integration for metrics (TTFT, processing latency, token usage)
- [ ] **EVNT-05**: Event pub/sub via Registry for in-process consumers

### Worker Infrastructure

- [ ] **WRKR-01**: WebSocket client connecting to LiveKit server agent protocol
- [ ] **WRKR-02**: Worker registration with heartbeat and status reporting
- [ ] **WRKR-03**: Job lifecycle: availability request -> assignment -> execution -> completion
- [ ] **WRKR-04**: OTP supervision tree: WorkerSupervisor -> Worker -> JobSupervisor -> AgentSession
- [ ] **WRKR-05**: Graceful shutdown via drain (stop accepting, wait for in-flight)
- [ ] **WRKR-06**: Load-based availability reporting (CPU/process metrics)

### Testing

- [x] **TEST-01**: 100% test coverage for all new behaviour modules
- [ ] **TEST-02**: 100% test coverage for ChatContext and tool system
- [ ] **TEST-03**: 100% test coverage for all provider implementations (using mock mode)
- [ ] **TEST-04**: 100% test coverage for pipeline, VAD, turn detection
- [ ] **TEST-05**: 100% test coverage for state machines and events
- [ ] **TEST-06**: 100% test coverage for worker infrastructure
- [ ] **TEST-07**: Integration tests for full STT -> LLM -> TTS flow (mock providers)

## v2 Requirements

### Additional Providers

- **PROV-01**: Anthropic Claude LLM provider
- **PROV-02**: ElevenLabs TTS provider
- **PROV-03**: AssemblyAI STT provider
- **PROV-04**: Silero VAD (ML-based via Nx/Ortex)

### Advanced Features

- **ADV-01**: OpenAI Realtime API (multimodal) support
- **ADV-02**: Agent handoff between multiple agents
- **ADV-03**: Fallback adapters (automatic failover to secondary provider)
- **ADV-04**: Stream adapters (non-streaming <-> streaming conversion)
- **ADV-05**: Transcription alignment (word-level timing)

## Out of Scope

| Feature | Reason |
|---------|--------|
| WebRTC room participation | Requires native client SDK bindings (Rust FFI) — separate project |
| Telephony/SIP support | Specialized infrastructure, defer to v2+ |
| Avatar/video generation | Specialized plugins, not core agent functionality |
| IVR workflows (DTMF, data collection) | Telephony-specific, defer |
| Answering machine detection | Telephony-specific |
| Background audio player | Nice-to-have, not core |
| MCP integration | Emerging standard, defer |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| BEHV-01 | Phase 1 | Complete |
| BEHV-02 | Phase 1 | Complete |
| BEHV-03 | Phase 1 | Complete |
| BEHV-04 | Phase 1 | Complete |
| BEHV-05 | Phase 1 | Complete |
| TEST-01 | Phase 1 | Complete |
| CHAT-01 | Phase 2 | Complete |
| CHAT-02 | Phase 2 | Complete |
| CHAT-03 | Phase 2 | Complete |
| CHAT-04 | Phase 2 | Complete |
| CHAT-05 | Phase 2 | Complete |
| CHAT-06 | Phase 2 | Complete |
| TEST-02 | Phase 2 | Pending |
| TOOL-01 | Phase 3 | Pending |
| TOOL-02 | Phase 3 | Pending |
| TOOL-03 | Phase 3 | Pending |
| TOOL-04 | Phase 3 | Pending |
| TOOL-05 | Phase 3 | Pending |
| DSTT-01 | Phase 4 | Pending |
| DSTT-02 | Phase 4 | Pending |
| DSTT-03 | Phase 4 | Pending |
| DSTT-04 | Phase 4 | Pending |
| DSTT-05 | Phase 4 | Pending |
| DSTT-06 | Phase 4 | Pending |
| OLLM-01 | Phase 5 | Pending |
| OLLM-02 | Phase 5 | Pending |
| OLLM-03 | Phase 5 | Pending |
| OLLM-04 | Phase 5 | Pending |
| OLLM-05 | Phase 5 | Pending |
| OLLM-06 | Phase 5 | Pending |
| OTTS-01 | Phase 6 | Pending |
| OTTS-02 | Phase 6 | Pending |
| OTTS-03 | Phase 6 | Pending |
| OTTS-04 | Phase 6 | Pending |
| OTTS-05 | Phase 6 | Pending |
| OTTS-06 | Phase 6 | Pending |
| TEST-03 | Phase 4, 5, 6 | Pending |
| PIPE-01 | Phase 7 | Pending |
| PIPE-02 | Phase 7 | Pending |
| PIPE-03 | Phase 7 | Pending |
| PIPE-04 | Phase 7 | Pending |
| PIPE-05 | Phase 7 | Pending |
| PIPE-06 | Phase 7 | Pending |
| TEST-04 | Phase 7 | Pending |
| TEST-07 | Phase 7 | Pending |
| EVNT-01 | Phase 8 | Pending |
| EVNT-02 | Phase 8 | Pending |
| EVNT-03 | Phase 8 | Pending |
| EVNT-04 | Phase 8 | Pending |
| EVNT-05 | Phase 8 | Pending |
| TEST-05 | Phase 8 | Pending |
| WRKR-01 | Phase 9 | Pending |
| WRKR-02 | Phase 9 | Pending |
| WRKR-03 | Phase 9 | Pending |
| WRKR-04 | Phase 9 | Pending |
| WRKR-05 | Phase 9 | Pending |
| WRKR-06 | Phase 9 | Pending |
| TEST-06 | Phase 9 | Pending |

**Coverage:**
- v1 requirements: 49 total
- Mapped to phases: 49
- Unmapped: 0

---
*Requirements defined: 2026-04-14*
*Last updated: 2026-04-14 — traceability updated after roadmap creation*

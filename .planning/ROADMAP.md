# Roadmap: LiveKit Elixir Agents Framework

## Overview

Starting from the existing LiveKit Elixir SDK (v0.1.4, mock agent implementations), this roadmap builds the full agents framework bottom-up: provider behaviours as contracts first, then chat context and tool calling as data plumbing, then real Deepgram/OpenAI provider implementations, then the streaming voice pipeline that connects them, then state machines and observability, and finally the worker infrastructure that connects agents to LiveKit rooms. Each phase delivers a coherent, independently testable capability. By the end a developer can build and deploy a working voice AI agent in pure Elixir.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Provider Behaviours** - Define the STT, TTS, LLM, and VAD contracts that all providers must implement (completed 2026-04-14)
- [x] **Phase 2: Chat Context** - Typed message structs and the ChatContext module for conversation history management (completed 2026-04-14)
- [x] **Phase 3: Tool System** - Tool specification, JSON schema generation, and the LLM function-calling execution loop (completed 2026-04-14)
- [x] **Phase 4: Deepgram STT** - Real Deepgram provider: batch HTTP and streaming WebSocket transcription (completed 2026-04-14)
- [x] **Phase 5: OpenAI LLM** - Real OpenAI provider: chat completions with SSE streaming and tool calling (completed 2026-04-14)
- [x] **Phase 6: OpenAI TTS** - Real OpenAI provider: audio synthesis with voice/format options and response caching (completed 2026-04-14)
- [x] **Phase 7: Voice Pipeline** - Streaming STT -> LLM -> TTS pipeline with VAD, turn detection, and interruption handling (completed 2026-04-14)
- [x] **Phase 8: State & Events** - User and agent state machines, typed events, :telemetry integration, and Registry pub/sub (completed 2026-04-14)
- [ ] **Phase 9: Worker Infrastructure** - WebSocket worker protocol, OTP supervision tree, job lifecycle, and graceful shutdown
- [ ] **Phase 10: Livebook Showcases** - Interactive Livebook tutorials for every framework feature (no API keys for most)

## Phase Details

### Phase 1: Provider Behaviours
**Goal**: Developer-facing behaviour contracts exist for all four provider types so any conforming module can be plugged into the pipeline
**Depends on**: Nothing (first phase)
**Requirements**: BEHV-01, BEHV-02, BEHV-03, BEHV-04, BEHV-05, TEST-01
**Success Criteria** (what must be TRUE):
  1. A module implementing `Livekit.Agents.STT` compiles without error and passes behaviour callback verification
  2. A module implementing `Livekit.Agents.TTS` compiles without error and passes behaviour callback verification
  3. A module implementing `Livekit.Agents.LLM` compiles without error and passes behaviour callback verification
  4. A module implementing `Livekit.Agents.VAD` compiles without error and passes behaviour callback verification
  5. Calling `capabilities/0` on any provider module returns a map declaring which optional features it supports
**Plans**: 3 plans
Plans:
- [x] 01-01-PLAN.md — Define STT behaviour (transcribe/2, stream/1, capabilities/0) + SpeechEvent struct
- [x] 01-02-PLAN.md — Define LLM behaviour (chat/2, stream/2, capabilities/0) + LLMChunk struct; VAD behaviour (stream/1, capabilities/0) + VADEvent struct
- [x] 01-03-PLAN.md — Conformance-stub tests for all four behaviours; 100% coverage gate

### Phase 2: Chat Context
**Goal**: Typed structs for conversation messages and a ChatContext module with safe truncation semantics
**Depends on**: Phase 1
**Requirements**: CHAT-01, CHAT-02, CHAT-03, CHAT-04, CHAT-05, CHAT-06, TEST-02
**Success Criteria** (what must be TRUE):
  1. Developer can construct a `ChatMessage` with role, content, and timestamp and pattern-match on it
  2. Developer can build a `ChatContext`, add messages, and retrieve ordered history
  3. Calling `truncate/2` on a `ChatContext` never drops the system message regardless of token budget
  4. `FunctionCall` and `FunctionCallOutput` structs round-trip through Jason encode/decode without data loss
  5. ChatContext accepts multi-modal content (plain text and structured maps) in message content
**Plans**: 2 plans
Plans:
- [x] 02-01-PLAN.md — ChatMessage, FunctionCall, FunctionCallOutput nested structs + ChatContext operations (add, truncate, merge, copy) with Jason.Encoder implementations
- [x] 02-02-PLAN.md — Full ExUnit test suite for all CHAT-0x requirements; 100% coverage gate

### Phase 3: Tool System
**Goal**: Tool definitions with JSON schema generation and an execution loop that feeds function call results back to the LLM
**Depends on**: Phase 2
**Requirements**: TOOL-01, TOOL-02, TOOL-03, TOOL-04, TOOL-05
**Success Criteria** (what must be TRUE):
  1. Developer can define a tool with a name, description, and parameter schema and it serializes to valid OpenAI function-calling JSON
  2. When the LLM returns a function call, the execution loop invokes the registered handler and feeds the result back automatically
  3. Setting `max_tool_steps: N` causes the loop to stop after N tool calls and return the final assistant message
  4. A tool handler returning `{:error, reason}` causes a `ToolError` that is surfaced back to the LLM as a function call output
**Plans**: 2 plans
Plans:
- [x] 03-01-PLAN.md — ToolSpec + ToolContext + ToolError structs; Tool.run/3 execution loop with max_tool_steps cap and error isolation
- [x] 03-02-PLAN.md — Full ExUnit test suite for all TOOL-0x requirements; 100% coverage gate

### Phase 4: Deepgram STT
**Goal**: Real Deepgram provider that implements the STT behaviour for both batch HTTP and streaming WebSocket transcription
**Depends on**: Phase 1
**Requirements**: DSTT-01, DSTT-02, DSTT-03, DSTT-04, DSTT-05, DSTT-06, TEST-03
**Success Criteria** (what must be TRUE):
  1. Calling `transcribe/2` with audio bytes sends a POST to Deepgram `/v1/listen` and returns a transcript struct
  2. Opening a streaming session delivers interim results as they arrive and a final transcript on silence
  3. Audio shorter than the configured minimum duration is buffered before sending to avoid empty-result responses
  4. All Deepgram calls pass `mix test` without a real API key when configured in mock mode
  5. The Deepgram module passes `Livekit.Agents.STT` behaviour verification at compile time
**Plans**: 3 plans
Plans:
- [x] 04-01-PLAN.md — Refactor deepgram.ex to implement @behaviour STT; real Tesla HTTP batch transcription; AudioBuffer helper; mock mode
- [x] 04-02-PLAN.md — DeepgramStream GenServer (Gun WebSocket); interim/final results; stream/1 callback on Deepgram module
- [x] 04-03-PLAN.md — Full ExUnit test suite: AudioBuffer unit tests, Deepgram HTTP tests (Bypass), DeepgramStream mock streaming tests

### Phase 5: OpenAI LLM
**Goal**: Real OpenAI LLM provider with SSE streaming, tool calling support, and token-aware conversation truncation
**Depends on**: Phase 1, Phase 2, Phase 3
**Requirements**: OLLM-01, OLLM-02, OLLM-03, OLLM-04, OLLM-05, OLLM-06, TEST-03
**Success Criteria** (what must be TRUE):
  1. Calling `chat/2` sends a POST to `/v1/chat/completions` and returns a `ChatMessage` with the assistant reply
  2. Streaming mode delivers partial text tokens to the caller as they arrive via SSE
  3. When the model requests a tool call, the provider formats the call and returns it as a `FunctionCall` struct
  4. `ChatContext` passed to the provider is automatically truncated to fit within the model's token limit
  5. All OpenAI LLM calls pass `mix test` without a real API key when configured in mock mode
**Plans**: 2 plans
Plans:
- [x] 05-01-PLAN.md — Refactor openai.ex to pure functional @behaviour LLM; chat/2 HTTP POST; stream/2 SSE; tool call parsing; token truncation; mock mode
- [x] 05-02-PLAN.md — Full ExUnit test suite: mock mode tests, Bypass HTTP tests, SSE streaming tests, message serialization tests

### Phase 6: OpenAI TTS
**Goal**: Real OpenAI TTS provider with configurable voices, audio format support, and response caching
**Depends on**: Phase 1
**Requirements**: OTTS-01, OTTS-02, OTTS-03, OTTS-04, OTTS-05, OTTS-06, TEST-03
**Success Criteria** (what must be TRUE):
  1. Calling `synthesize/2` with text sends a POST to `/v1/audio/speech` and returns audio bytes in the requested format
  2. All six OpenAI voices (alloy, echo, fable, onyx, nova, shimmer) can be selected via configuration and produce audio
  3. Audio format selection (PCM, MP3, Opus, AAC, FLAC) changes the Content-Type and encoding of the returned bytes
  4. Synthesizing the same text twice within TTL returns the cached result without a second HTTP request
  5. All OpenAI TTS calls pass `mix test` without a real API key when configured in mock mode
**Plans**: 2 plans
Plans:
- [x] 06-01-PLAN.md — Refactor openai.ex to pure functional @behaviour TTS; real HTTP POST to /v1/audio/speech; Cache Agent module; mock mode with sine wave
- [x] 06-02-PLAN.md — Full ExUnit test suite: Cache unit tests, Bypass HTTP tests, mock mode tests, cache hit verification

### Phase 7: Voice Pipeline
**Goal**: Streaming STT -> LLM -> TTS pipeline with energy-based VAD, configurable turn detection, and interruption handling
**Depends on**: Phase 4, Phase 5, Phase 6
**Requirements**: PIPE-01, PIPE-02, PIPE-03, PIPE-04, PIPE-05, PIPE-06, TEST-04, TEST-07
**Success Criteria** (what must be TRUE):
  1. Audio frames pushed into the pipeline flow through STT -> LLM -> TTS without the producer blocking on slow consumers (backpressure works)
  2. Energy-based VAD correctly classifies speech vs silence frames with configurable threshold
  3. A speaking turn ends after configurable silence duration elapses, triggering LLM processing
  4. New user speech detected while TTS is playing cancels the current synthesis and restarts the STT -> LLM -> TTS cycle
  5. Any STT/LLM/TTS module implementing the provider behaviours can be swapped into the pipeline without code changes
  6. :telemetry events are emitted at each stage (stt_complete, llm_first_token, tts_start) with timing metadata
**Plans**: 3 plans
Plans:
- [x] 07-01-PLAN.md — EnergyVAD pure module (classify/2 via AudioFrame.is_silence?); TurnDetector GenServer (timer-based turn boundaries)
- [x] 07-02-PLAN.md — Pipeline GenServer rewrite: push_frame/2 cast, Task.async STT->LLM->TTS, interruption, ChatContext ownership, :telemetry events
- [x] 07-03-PLAN.md — Full ExUnit test suite: EnergyVAD unit, TurnDetector unit, Pipeline integration with inline mock providers

### Phase 8: State & Events
**Goal**: User and agent state machines with typed event structs, :telemetry metrics, and Registry-based pub/sub
**Depends on**: Phase 7
**Requirements**: EVNT-01, EVNT-02, EVNT-03, EVNT-04, EVNT-05, TEST-05
**Success Criteria** (what must be TRUE):
  1. The user state machine transitions listening -> speaking -> away on voice activity and timeout events
  2. The agent state machine transitions initializing -> listening -> thinking -> speaking in response to pipeline stages
  3. All state transitions emit typed event structs that consumers can pattern-match on
  4. :telemetry measurements for TTFT, end-to-end latency, and token counts are emitted and capturable in tests
  5. A process can subscribe via Registry and receive all conversation events without polling
**Plans**: 2 plans
Plans:
- [x] 08-01-PLAN.md — Events structs + UserStateMachine + AgentStateMachine GenServers + EventBus (Registry pub/sub + :telemetry bridge)
- [x] 08-02-PLAN.md — Full ExUnit test suite for all EVNT-0x requirements and TEST-05; 100% coverage gate

### Phase 9: Worker Infrastructure
**Goal**: WebSocket worker protocol, OTP supervision tree, full job lifecycle, graceful drain, and load reporting
**Depends on**: Phase 8
**Requirements**: WRKR-01, WRKR-02, WRKR-03, WRKR-04, WRKR-05, WRKR-06, TEST-06
**Success Criteria** (what must be TRUE):
  1. The worker connects to a LiveKit server via WebSocket and successfully completes the agent registration handshake
  2. The worker sends periodic heartbeats and updates its availability status; the server can detect a dead worker
  3. When a job is assigned, an AgentSession is spawned under its own supervisor and runs to completion or crash-restarts in isolation
  4. The OTP supervision tree (WorkerSupervisor -> Worker -> JobSupervisor -> AgentSession) starts cleanly and each level restarts independently
  5. Calling drain stops the worker from accepting new jobs and waits for all in-flight sessions to complete before shutting down
  6. Worker availability reporting reflects current process load metrics
**Plans**: 2 plans
Plans:
- [x] 09-01-PLAN.md — Gun dep + WorkerSupervisor (one_for_one) + JobSupervisor (DynamicSupervisor) + Worker refactor (Gun WebSocket, heartbeat, drain, load)
- [ ] 09-02-PLAN.md — Full ExUnit test suite for all WRKR-0x requirements and TEST-06; mock mode only

### Phase 10: Livebook Showcases
**Goal**: Interactive Livebook tutorials covering every feature of the LiveKit Elixir Agents framework; each accepts API keys via Kino.Input; most work without any keys
**Depends on**: Phase 9
**Requirements**: LB-01, LB-02, LB-03, LB-04, LB-05, LB-06, LB-07, LB-08, LB-09
**Plans**: 3 plans

Plans:
- [ ] 10-01-PLAN.md — Livebooks 01-03: provider behaviours, chat context, tool calling (no API keys)
- [x] 10-02-PLAN.md — Livebooks 04-06: Deepgram STT, OpenAI LLM, OpenAI TTS (API keys + mock mode)
- [ ] 10-03-PLAN.md — Livebooks 07-09: voice pipeline, state/events, worker infrastructure (no API keys)

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9 -> 10

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Provider Behaviours | 3/3 | Complete   | 2026-04-14 |
| 2. Chat Context | 2/2 | Complete   | 2026-04-14 |
| 3. Tool System | 2/2 | Complete   | 2026-04-14 |
| 4. Deepgram STT | 3/3 | Complete   | 2026-04-14 |
| 5. OpenAI LLM | 2/2 | Complete   | 2026-04-14 |
| 6. OpenAI TTS | 2/2 | Complete   | 2026-04-14 |
| 7. Voice Pipeline | 3/3 | Complete   | 2026-04-14 |
| 8. State & Events | 2/2 | Complete   | 2026-04-14 |
| 9. Worker Infrastructure | 1/2 | In Progress|  |
| 10. Livebook Showcases | 1/3 | In Progress|  |

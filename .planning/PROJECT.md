# LiveKit Elixir Agents Framework

## What This Is

A production-grade agents framework for the LiveKit Elixir SDK that enables developers to build real-time voice AI agents in Elixir/OTP. It provides composable STT -> LLM -> TTS voice pipelines, pluggable AI provider integrations, and the worker/session infrastructure to connect agents to LiveKit rooms — bringing feature parity with the Python LiveKit Agents framework while leveraging OTP's natural strengths for concurrent, fault-tolerant agent systems.

## Core Value

A developer can build and deploy a working voice AI agent using only Elixir — connecting to a LiveKit room, transcribing speech, generating responses via LLM, and speaking back — with real provider integrations, not mocks.

## Requirements

### Validated

- Room management API client (Twirp/HTTP+Protobuf) — existing
- Access token JWT generation — existing
- Egress/Ingress service clients — existing
- Webhook receiver — existing
- Protobuf message definitions — existing
- AudioFrame data structure with format conversion — existing

### Active

- [ ] Elixir behaviours for STT, TTS, LLM, VAD provider contracts
- [ ] Real Deepgram STT integration (HTTP + WebSocket streaming)
- [ ] Real OpenAI LLM integration (HTTP with SSE streaming)
- [ ] Real OpenAI TTS integration (HTTP chunked responses)
- [ ] Proper ChatContext with typed structs (ChatMessage, FunctionCall, FunctionCallOutput)
- [ ] Tool/function calling system with execution loop
- [ ] Streaming voice pipeline with backpressure (GenStage or manual)
- [ ] VAD implementation (energy-based or ML-based)
- [ ] Turn detection (VAD-based with configurable endpointing)
- [ ] Interruption handling (cancel and restart)
- [ ] User/Agent state machines
- [ ] Event system via :telemetry and Registry
- [ ] Worker WebSocket protocol (register, heartbeat, job assignment)
- [ ] OTP supervision tree (worker -> job -> session hierarchy)
- [ ] 100% test coverage for all new code

### Out of Scope

- WebRTC room participation (requires native client SDK bindings) — defer to separate effort
- OpenAI Realtime API (multimodal) — future phase
- Avatar/video generation — future phase
- Telephony/SIP support — future phase
- IVR workflows (DTMF, address collection) — future phase
- Agent handoff between multiple agents — future phase
- Answering machine detection — future phase
- Background audio player — future phase

## Context

- **Existing codebase**: LiveKit Elixir SDK v0.1.4 on `agents` branch with mock agent implementations
- **Reference**: Python LiveKit Agents framework (80+ plugins, production-grade)
- **Gap analysis**: All agent subsystems (STT, LLM, TTS, worker, session) currently use mock implementations
- **Natural advantages**: OTP supervision trees, GenServer state machines, GenStage for streaming, :telemetry for observability, lightweight processes for concurrent sessions

## Constraints

- **Tech stack**: Elixir ~> 1.15, OTP, existing dependencies (Tesla, Jason, Joken, Protobuf, gRPC)
- **Compatibility**: Must not break existing core SDK functionality (room service, tokens, webhooks)
- **Testing**: 100% test coverage required — use Bypass for HTTP, Mock for function mocking, ExUnit
- **API keys**: All provider integrations must work with mock mode for tests (no real API calls in CI)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use behaviours over protocols | Providers implement full interface as a module, not per-data-type dispatch | -- Pending |
| GenStage for pipeline streaming | Backpressure-aware, built for producer-consumer chains | -- Pending |
| :telemetry for metrics/events | Idiomatic Elixir, integrates with Phoenix/Ecto ecosystem | -- Pending |
| Energy-based VAD first | Simpler than ML, no additional dependencies, good enough for MVP | -- Pending |
| Keep mock mode alongside real | Tests run without API keys, dev can work offline | -- Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? -> Move to Out of Scope with reason
2. Requirements validated? -> Move to Validated with phase reference
3. New requirements emerged? -> Add to Active
4. Decisions to log? -> Add to Key Decisions
5. "What This Is" still accurate? -> Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-14 after initialization*

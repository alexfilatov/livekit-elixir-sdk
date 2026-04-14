<!-- GSD:project-start source:PROJECT.md -->
## Project

**LiveKit Elixir Agents Framework**

A production-grade agents framework for the LiveKit Elixir SDK that enables developers to build real-time voice AI agents in Elixir/OTP. It provides composable STT -> LLM -> TTS voice pipelines, pluggable AI provider integrations, and the worker/session infrastructure to connect agents to LiveKit rooms — bringing feature parity with the Python LiveKit Agents framework while leveraging OTP's natural strengths for concurrent, fault-tolerant agent systems.

**Core Value:** A developer can build and deploy a working voice AI agent using only Elixir — connecting to a LiveKit room, transcribing speech, generating responses via LLM, and speaking back — with real provider integrations, not mocks.

### Constraints

- **Tech stack**: Elixir ~> 1.15, OTP, existing dependencies (Tesla, Jason, Joken, Protobuf, gRPC)
- **Compatibility**: Must not break existing core SDK functionality (room service, tokens, webhooks)
- **Testing**: 100% test coverage required — use Bypass for HTTP, Mock for function mocking, ExUnit
- **API keys**: All provider integrations must work with mock mode for tests (no real API calls in CI)
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Language & Runtime
- **Language:** Elixir ~> 1.15
- **Runtime:** BEAM (Erlang/OTP)
- **Build Tool:** Mix
- **Package:** `livekit` v0.1.4 on Hex
- **License:** Apache-2.0
## Core Dependencies
### HTTP & Network
| Dependency | Version | Purpose | Used In |
|-----------|---------|---------|---------|
| `tesla` | ~> 1.7 | HTTP client | `room_service_client.ex`, all agent API clients |
| `hackney` | ~> 1.18 | HTTP adapter for Tesla | Transport layer |
| `mint` | ~> 1.7.1 | Alternative HTTP adapter | Optional |
| `gun` | ~> 2.2.0 | WebSocket & HTTP/2 | gRPC, Deepgram streaming |
### Protocol Buffers & gRPC
| Dependency | Version | Purpose | Used In |
|-----------|---------|---------|---------|
| `protobuf` | ~> 0.14.1 | Protobuf serialization | `lib/livekit/proto/*.pb.ex` |
| `grpc` | ~> 0.10.2 | gRPC framework | `egress_service_client.ex` |
### Authentication & JWT
| Dependency | Version | Purpose | Used In |
|-----------|---------|---------|---------|
| `joken` | ~> 2.6.2 | JWT generation/validation | `access_token.ex` |
| `jose` | ~> 1.11.10 | JOSE crypto operations | HS256 signing |
### JSON & Data
| Dependency | Version | Purpose | Used In |
|-----------|---------|---------|---------|
| `jason` | ~> 1.4.4 | JSON encode/decode | All API clients |
| `inflex` | ~> 2.1.0 | String inflection | camelCase conversion for JWT |
### Streaming & Pipeline
| Dependency | Version | Purpose | Used In |
|-----------|---------|---------|---------|
| `gen_stage` | ~> 1.3.2 | Producer-consumer pattern | gRPC dependency |
| `flow` | ~> 1.2.4 | Data processing pipelines | gRPC dependency |
## Dev Dependencies
| Dependency | Version | Purpose |
|-----------|---------|---------|
| `ex_doc` | ~> 0.29 | Documentation generation |
| `credo` | ~> 1.7 | Code linting |
| `dialyxir` | ~> 1.4 | Static type analysis |
| `bypass` | ~> 2.1.0 | HTTP mocking for tests |
| `mock` | ~> 0.3.0 | Mocking library |
| `excoveralls` | ~> 0.18 | Code coverage |
## Configuration
### Files
- `config/config.exs` — Base config (Joken signer)
- `config/runtime.exs` — Reads `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`
- `config/dev.exs` — Debug logging
- `config/test.exs` — Info logging, custom formatter
- `config/prod.exs` — JSON logging, sensitive header filtering
### Configuration Module
- `lib/livekit/config.ex` — Merges runtime options > app env > env vars
- Type: `%Livekit.Config{url, api_key, api_secret}`
## Custom Build
- Proto compiler: `lib/mix/tasks/compile.proto.ex`
- Compiles `.proto` files to `lib/livekit/proto/*.pb.ex`
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Formatting & Linting
- **Formatter**: `mix format` with `.formatter.exs` (inputs: `{config,lib,test}/**/*.{ex,exs}`)
- **Linter**: Credo with `strict: true` (`.credo.exs`)
- **Max line length**: 120 chars (low priority)
- **CI**: `mix format --check-formatted` + `mix credo --strict`
## Module Structure Pattern
## GenServer Conventions
## Error Handling
## Naming
- **Modules**: PascalCase dot-notation (`Livekit.Agents.STT.Deepgram`)
- **Functions**: snake_case with prefixes: `get_*`, `with_*`, `add_*`, `validate_*`
- **Variables**: descriptive snake_case (`audio_data`, `participant_identity`)
- **Builder pattern**: `with_*` functions returning modified struct
|> AccessToken.with_identity("user123")
|> AccessToken.with_ttl(3600)
|> AccessToken.to_jwt()
## Provider Injection
## Documentation
- `@moduledoc` required on all public modules (Credo enforced)
- `@doc` on all public functions with examples for complex ones
- `@spec` on all public functions and GenServer callbacks
## Configuration Precedence
## Metrics Pattern
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## Architectural Pattern: OTP/GenServer
## Layers
```
```
## Key Components
### Worker (`lib/livekit/agents/worker.ex`)
- Top-level job dispatcher
- Registers with LiveKit server (WebSocket — currently mocked)
- Spawns AgentSession per job
- Health monitoring with heartbeat
- Configurable max concurrent jobs (default: 10)
### AgentSession (`lib/livekit/agents/agent_session.ex`)
- Connects to LiveKit room (WebRTC — currently mocked)
- Tracks participants and audio/video tracks
- Routes audio frames to VoiceAgent
- Sends agent responses back to room
### VoiceAgent (`lib/livekit/agents/voice_agent.ex`)
- Orchestrates STT/LLM/TTS pipeline
- Maintains conversation context (list of `{type, content, timestamp}`)
- Turn detection (multilingual/simple) and VAD config
- Preemptive synthesis option
### Pipeline (`lib/livekit/agents/pipeline.ex`)
- Composable STT → LLM → TTS node chain
- Each node wraps a provider GenServer
- Falls back to mock nodes on initialization failure
### AudioFrame (`lib/livekit/agents/audio_frame.ex`)
- Standard audio data unit throughout pipeline
- Supports PCM16/24/32 and Float32 formats
- Operations: resample, convert, mix, split channels, silence detection, WAV parsing
### JobContext (`lib/livekit/agents/job_context.ex`)
- Pure data struct (not a GenServer)
- Job metadata, room token generation, secret sanitization
## AI Providers
| Provider | File | Protocol | Status |
|----------|------|----------|--------|
| Deepgram STT | `lib/livekit/agents/stt/deepgram.ex` | HTTP + WebSocket | Mocked |
| OpenAI LLM | `lib/livekit/agents/llm/openai.ex` | HTTP REST | Mocked |
| OpenAI TTS | `lib/livekit/agents/tts/openai.ex` | HTTP REST | Mocked |
## Data Flow
```
```
## Communication Patterns
- **Synchronous** (`GenServer.call`): status queries, config updates (5-15s timeouts)
- **Asynchronous** (`GenServer.cast`): audio frame processing, fire-and-forget
- **Process monitoring**: Worker monitors sessions, sessions monitor voice agents
## Core SDK (Non-Agent)
- `lib/livekit/room_service_client.ex` — Twirp HTTP+Protobuf client for room CRUD
- `lib/livekit/access_token.ex` — JWT generation with builder pattern
- `lib/livekit/grants.ex` — Permission model
- `lib/livekit/egress_service_client.ex` — gRPC client for recording
- `lib/livekit/ingress_service_client.ex` — Ingress management
- `lib/livekit/webhook_receiver.ex` — Webhook validation and parsing
- `lib/livekit/config.ex` — 4-level config precedence (runtime > app env > env vars > defaults)
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, or `.github/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->

# LiveKit Elixir SDK - Architecture

## Architectural Pattern: OTP/GenServer

Built on OTP principles — each major component is an independent GenServer process with fault isolation via supervision trees.

## Layers

```
Mix Tasks (livekit.agents.start, livekit.agents.dev)
    |
Worker Layer (job dispatch, server registration, health monitoring)
    |
Agent Session Layer (room connection, participant tracking, audio routing)
    |
Voice Agent + Pipeline Layer (STT -> LLM -> TTS orchestration)
    |
Core SDK Layer (RoomServiceClient, AccessToken, Webhooks, Protobuf)
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

Provider injection via `{module, config}` tuples in VoiceAgent.Config.

## Data Flow

```
WebRTC Audio -> AgentSession -> VoiceAgent -> Pipeline
  -> STT Node (Deepgram): AudioFrame -> transcript text
  -> LLM Node (OpenAI): text -> response text
  -> TTS Node (OpenAI): response -> AudioFrame
VoiceAgent <- Pipeline result
AgentSession <- response audio
WebRTC Output -> room participants
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

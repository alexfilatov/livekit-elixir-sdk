# LiveKit Elixir SDK - External Integrations

## LiveKit Server API

### HTTP/Protobuf (Room Service)
- **File:** `lib/livekit/room_service_client.ex`
- **Protocol:** HTTP + Protocol Buffers
- **Adapter:** Tesla/Hackney
- **Auth:** Bearer token (`api_key:api_secret`)
- **Endpoints:** Twirp RPC (`/twirp/livekit.RoomService/*`)
  - CreateRoom, DeleteRoom, ListRooms
  - ListParticipants, UpdateParticipant, RemoveParticipant
  - MuteRoomTrack, SendData, UpdateRoomMetadata, UpdateSubscriptions

### gRPC (Egress Service)
- **File:** `lib/livekit/egress_service_client.ex`
- **Protocol:** gRPC over HTTP/2
- **Library:** `grpc ~> 0.10.2`
- **Endpoints:** `livekit.EgressService/*`
  - ListEgress, StartRoomCompositeEgress, StartTrackEgress, StopEgress

### Agent Dispatch (WebSocket)
- **File:** `lib/livekit/agents/worker.ex`
- **Protocol:** WebSocket (currently mocked)
- **Messages:** `RoomAgentDispatch`, `InitRequest` (protobuf)
- **Status:** Mock implementation — needs real WebSocket client

### Webhooks
- **File:** `lib/livekit/webhook_receiver.ex`
- **Protocol:** HTTP POST with JWT validation
- **Events:** room_started/finished, participant_joined/left, track_published/unpublished, etc.

## OpenAI API

### Chat Completions (LLM)
- **File:** `lib/livekit/agents/llm/openai.ex`
- **Endpoint:** `https://api.openai.com/v1/chat/completions`
- **Auth:** Bearer token
- **Default model:** `gpt-4o-mini`
- **Features:** Conversation history, tool/function calling, temperature control
- **Status:** Mock responses — needs real HTTP calls

### Text-to-Speech
- **File:** `lib/livekit/agents/tts/openai.ex`
- **Endpoint:** `https://api.openai.com/v1/audio/speech`
- **Auth:** Bearer token
- **Default model:** `tts_1`
- **Voices:** alloy, echo, fable, onyx, nova, shimmer
- **Formats:** PCM, MP3, Opus, AAC, FLAC
- **Status:** Mock sine wave generation — needs real HTTP calls

## Deepgram API (STT)

- **File:** `lib/livekit/agents/stt/deepgram.ex`
- **HTTP endpoint:** `https://api.deepgram.com/v1/listen`
- **WebSocket:** `wss://api.deepgram.com/v1/listen` (streaming)
- **Auth:** `Token <api_key>`
- **Default model:** `nova-2`
- **Features:** Streaming, batch, VAD, diarization, interim results
- **Status:** Mock transcription — needs real HTTP/WebSocket calls

## Protocol Buffers

### Proto Files (`proto/`)
| File | Purpose |
|------|---------|
| `livekit_models.proto` | Room, Participant, Track, Codec definitions |
| `livekit_room.proto` | RoomService RPC definitions |
| `livekit_egress.proto` | Recording/streaming operations |
| `livekit_ingress.proto` | External stream input (RTMP, WHIP, URL) |
| `livekit_webhook.proto` | Webhook event structure |
| `livekit_agent_dispatch.proto` | Agent dispatch messages (minimal) |

### Generated Modules (`lib/livekit/proto/`)
- `livekit_models.pb.ex`, `livekit_room.pb.ex`, `livekit_egress.pb.ex`
- `livekit_ingress.pb.ex`, `livekit_webhook.pb.ex`, `livekit_agent_dispatch.pb.ex`

## JWT Authentication
- **File:** `lib/livekit/access_token.ex`
- **Library:** Joken + JOSE
- **Algorithm:** HS256
- **Claims:** iss (API key), sub (identity), exp, nbf, video grants, metadata

## Integration Summary

| Service | Protocol | Auth | Status |
|---------|----------|------|--------|
| LiveKit Room API | HTTP+Protobuf | Bearer | Working |
| LiveKit Egress | gRPC/HTTP2 | Bearer | Working |
| LiveKit Agent Dispatch | WebSocket | Bearer | Mocked |
| OpenAI Chat | HTTP/REST | Bearer | Mocked |
| OpenAI TTS | HTTP/REST | Bearer | Mocked |
| Deepgram STT | HTTP+WebSocket | Token | Mocked |
| Webhooks | HTTP POST | JWT | Working |

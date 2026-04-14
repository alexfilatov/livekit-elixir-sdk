# Phase 11: WebRTC Room Client (Rustler NIFs) - Context

**Gathered:** 2026-04-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Create Elixir bindings to the LiveKit WebRTC client SDK via Rustler NIFs. This enables Elixir agents to join LiveKit rooms as participants, receive audio/video tracks, and publish audio/video tracks. Uses `livekit-client-sdk-rust` (the official Rust client) wrapped via Rustler for native Elixir integration.

</domain>

<decisions>
## Implementation Decisions

### Architecture
- **D-01:** Use Rustler to create NIF bindings to `livekit-client-sdk-rust`
- **D-02:** The Rust crate lives in `native/livekit_webrtc/` following Rustler conventions
- **D-03:** Elixir wrapper modules in `lib/livekit/webrtc/` provide idiomatic Elixir API
- **D-04:** NIF resources wrap Rust Room, Track, and Participant objects
- **D-05:** Audio frames flow as binaries between Rust and Elixir (zero-copy where possible)

### Core Modules
- **D-06:** `Livekit.WebRTC.Room` — connect/disconnect, participant events, data channels
- **D-07:** `Livekit.WebRTC.AudioTrack` — subscribe to remote audio, publish local audio
- **D-08:** `Livekit.WebRTC.VideoTrack` — subscribe to remote video, publish local video (basic)
- **D-09:** `Livekit.WebRTC.Participant` — identity, metadata, track listing
- **D-10:** Room events dispatched to Elixir process via message passing (not polling)

### Event Model
- **D-11:** Rust side spawns a tokio task per Room that forwards events to a registered Elixir PID
- **D-12:** Events: participant_connected/disconnected, track_subscribed/unsubscribed, track_published/unpublished, data_received, connection_quality_changed, disconnected
- **D-13:** Audio frames from subscribed tracks sent as `{:audio_frame, track_sid, binary}` messages
- **D-14:** Use `rustler::Env::send` for async event dispatch from Rust to Elixir

### Dependencies
- **D-15:** Add `rustler ~> 0.35` to mix.exs
- **D-16:** Add `livekit` and `livekit-api` Rust crates as dependencies in native/livekit_webrtc/Cargo.toml
- **D-17:** Rust toolchain required (rustc, cargo) — document in README
- **D-18:** Use `tokio` runtime in Rust for async WebRTC operations

### Testing
- **D-19:** Unit tests for Elixir wrapper modules with mock NIF responses
- **D-20:** Integration tests connecting to a local LiveKit server (docker-compose)
- **D-21:** Test audio round-trip: publish from Elixir -> receive in Elixir via second participant

### Claude's Discretion
- Exact Rustler resource struct design
- Error handling strategy across the NIF boundary
- Whether to use dirty schedulers for blocking operations
- Audio resampling on the Rust side vs Elixir side

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/livekit/agents/audio_frame.ex` — AudioFrame struct for audio data
- `lib/livekit/access_token.ex` — JWT token generation for room access
- `examples/docker/docker-compose.yml` — local LiveKit server for testing

### Integration Points
- `AgentSession` will use `Livekit.WebRTC.Room` instead of mock room connection
- `Pipeline` receives audio from `Room` audio tracks via messages
- `Pipeline` publishes synthesized audio back to the room via `AudioTrack`

</code_context>

<specifics>
## Specific Ideas

- Follow the pattern of `ex_webrtc` and `membrane_core` for NIF design in Elixir
- The Rust crate `livekit` (https://crates.io/crates/livekit) is the official client SDK
- Keep the NIF surface area minimal — just room connect, track subscribe/publish, event forwarding
- Complex audio processing stays in Elixir (pipeline, VAD, etc.)

</specifics>

<deferred>
## Deferred Ideas

None — this is the critical connectivity layer.

</deferred>

---

*Phase: 11-webrtc-room-client-rustler-nifs*
*Context gathered: 2026-04-14*

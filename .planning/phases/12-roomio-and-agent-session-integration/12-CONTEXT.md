# Phase 12: RoomIO and Agent Session Integration - Context

**Gathered:** 2026-04-14
**Status:** Ready for planning
**Mode:** Auto-generated (integration phase)

<domain>
## Phase Boundary

Connect the WebRTC Room Client (Phase 11) to the Agent Pipeline (Phase 7). RoomIO bridges room audio tracks to the pipeline input/output. AgentSession is refactored to use real Room connections instead of mocks. Audio flows: Room -> RoomIO -> Pipeline -> RoomIO -> Room.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
Key constraints:
- Create `Livekit.Agents.RoomIO` module that:
  - Subscribes to remote participant audio tracks via WebRTC.Room
  - Forwards audio frames to the Pipeline via push_frame
  - Receives {:pipeline_audio, frame} and publishes back to the room
- Refactor `AgentSession` to:
  - Use `Livekit.WebRTC.Room` for real room connection (replacing mock)
  - Create RoomIO to bridge room audio <-> pipeline
  - Keep mock mode for testing (when server_url is nil)
- RoomIO as a GenServer that owns the audio routing lifecycle
- Handle participant join/leave — subscribe to new participants, unsubscribe on leave
- Auto-subscribe to first participant's audio track (configurable)
- Convert between WebRTC audio format (PCM int16 binary) and AudioFrame structs

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- lib/livekit/webrtc/room.ex — Room GenServer (Phase 11)
- lib/livekit/webrtc/audio_track.ex — Audio subscribe/publish
- lib/livekit/agents/pipeline.ex — Pipeline GenServer (Phase 7)
- lib/livekit/agents/agent_session.ex — Current mock session
- lib/livekit/agents/audio_frame.ex — AudioFrame struct

### Integration Points
- RoomIO sits between WebRTC.Room and Pipeline
- AgentSession orchestrates Room + RoomIO + Pipeline lifecycle

</code_context>

<specifics>
## Specific Ideas

- Follow Python agents' RoomIO pattern: input options + output options per participant
- Keep it simple for v1: auto-subscribe to first remote participant

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>

---

*Phase: 12-roomio-and-agent-session-integration*
*Context gathered: 2026-04-14*

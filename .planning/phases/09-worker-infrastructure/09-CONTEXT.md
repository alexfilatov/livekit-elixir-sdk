# Phase 9: Worker Infrastructure - Context

**Gathered:** 2026-04-14
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase)

<domain>
## Phase Boundary

WebSocket worker protocol for connecting to LiveKit server, OTP supervision tree (WorkerSupervisor -> Worker -> JobSupervisor -> AgentSession), full job lifecycle (availability -> assignment -> execution -> completion), graceful shutdown via drain, and load-based availability reporting.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
Key constraints:
- Refactor existing `lib/livekit/agents/worker.ex` to use real WebSocket connection
- Use Gun for WebSocket client (already in deps)
- Worker protocol: register with LiveKit server, send heartbeats, receive job assignments
- OTP supervision tree:
  - WorkerSupervisor (top-level, one_for_one)
  - Worker (registers with server, manages jobs)
  - JobSupervisor (DynamicSupervisor for agent sessions)
  - AgentSession (per-job, supervised)
- Job lifecycle: server sends availability request -> worker accepts/rejects -> server sends assignment -> worker spawns session
- Graceful drain: stop accepting new jobs, wait for in-flight sessions to complete
- Load reporting: track active jobs vs max_concurrent_jobs, report availability
- Heartbeat interval configurable (default 30s)
- Reconnect with exponential backoff on disconnect
- Keep mock mode for testing (no real server needed)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/livekit/agents/worker.ex` — existing mock worker with correct config/state structs
- `lib/livekit/agents/agent_session.ex` — existing session module
- `lib/livekit/proto/livekit_agent_dispatch.pb.ex` — protobuf messages for agent dispatch

### Integration Points
- Worker spawns AgentSession which creates Pipeline
- Pipeline uses all the providers built in Phases 4-6
- State machines from Phase 8 track agent/user states
- EventBus publishes events from agent sessions

</code_context>

<specifics>
## Specific Ideas

No specific requirements — follow OTP best practices.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>

---

*Phase: 09-worker-infrastructure*
*Context gathered: 2026-04-14*

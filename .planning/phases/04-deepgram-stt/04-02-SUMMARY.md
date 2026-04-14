---
phase: 04-deepgram-stt
plan: "02"
subsystem: stt
tags: [elixir, genserver, websocket, gun, deepgram, streaming, speech-to-text]

requires:
  - phase: 04-01
    provides: Deepgram.Config struct, AudioBuffer helper, STT behaviour implementation

provides:
  - DeepgramStream GenServer managing Gun WebSocket connection to Deepgram /v1/listen
  - stream/1 callback on Livekit.Agents.STT.Deepgram completing the full STT behaviour contract
  - send_audio/2 and finish/1 client API on DeepgramStream
  - Mock streaming mode emitting synthetic start/interim/final/end event sequence

affects: [voice-pipeline, agent-session, phase-7]

tech-stack:
  added: []
  patterns:
    - "GenServer with async :connect init pattern (send self :connect from init/1)"
    - "Gun WebSocket lifecycle via handle_info :gun_upgrade/:gun_ws/:gun_down"
    - "Mock GenServer that spawns side process and stops via :mock_done cast"

key-files:
  created:
    - lib/livekit/agents/stt/deepgram_stream.ex
  modified:
    - lib/livekit/agents/stt/deepgram.ex

key-decisions:
  - "Mock mode implemented as a live GenServer that spawns task and stops via :mock_done cast, ensuring stream/1 always returns {:ok, pid}"
  - "Audio buffering uses existing AudioBuffer with nil guard in handle_cast :finish for mock state"
  - "build_ws_headers/1 uses charlists for Gun compatibility, api_key is not logged"
  - "handle_info catch-all clause added to prevent unhandled message crashes from unexpected Gun frames"

patterns-established:
  - "DeepgramStream.State uses :connected boolean flag to gate audio flushing before WebSocket upgrade"
  - "Jason.decode (not decode!) used for all Deepgram frame parsing — parse errors log warning, no crash"

requirements-completed: [DSTT-02, DSTT-03]

duration: 35min
completed: 2026-04-14
---

# Phase 4 Plan 02: Deepgram STT WebSocket Streaming Summary

**DeepgramStream GenServer connecting to wss://api.deepgram.com/v1/listen via Gun, emitting {:speech_event, %SpeechEvent{}} to subscriber with interim/final/end lifecycle**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-04-14T10:18:00Z
- **Completed:** 2026-04-14T10:53:59Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Created `DeepgramStream` GenServer that owns a Gun WebSocket connection to `wss://api.deepgram.com/v1/listen`
- Implemented full Gun WebSocket lifecycle: `:gun_upgrade` (connected), `:gun_ws` (incoming frames), `:gun_down` (connection lost)
- Added `stream/1` callback to `Livekit.Agents.STT.Deepgram`, completing the full STT behaviour contract
- Mock mode spawns synthetic `start → interim → final → end` event sequence without a real WebSocket connection

## Task Commits

1. **Task 1: Implement DeepgramStream GenServer** - `5c079b5` (feat)
2. **Task 2: Add stream/1 callback to Deepgram module** - `bac8cf2` (feat)

## Files Created/Modified

- `lib/livekit/agents/stt/deepgram_stream.ex` — New GenServer: Gun WebSocket connection, audio buffering, frame parsing, mock mode
- `lib/livekit/agents/stt/deepgram.ex` — Added `stream/1` callback delegating to `DeepgramStream.start_link/1`

## Decisions Made

- **Mock mode as live GenServer**: The plan's initial mock approach used `{:stop, :normal}` in `init/1` which would return `{:error, :normal}` from `start_link`. Implemented mock mode as a running GenServer that spawns the event task and stops via a `:mock_done` cast — ensures `stream/1` always returns `{:ok, pid}` as the behaviour contract requires.
- **Nil guard on AudioBuffer in finish/1**: Mock mode's `State` has `buffer: nil`, so `handle_cast :finish` guards `if state.buffer` before calling `AudioBuffer.flush/1`.
- **Catch-all handle_info**: Added a catch-all `handle_info(_msg, state)` clause to silently drop unrecognized Gun messages rather than crashing on unexpected frames.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Mock init {:stop, :normal} would return {:error, :normal} from start_link**
- **Found during:** Task 1 (DeepgramStream GenServer implementation)
- **Issue:** Plan's mock `init/1` used `{:stop, :normal}` which causes `GenServer.start_link` to return `{:error, :normal}`, violating the `stream/1` contract of `{:ok, pid}`
- **Fix:** Mock init returns `{:ok, state}` and spawns the event task; mock task sends `:mock_done` cast back to server which stops normally via `handle_cast(:mock_done, state)`
- **Files modified:** `lib/livekit/agents/stt/deepgram_stream.ex`
- **Verification:** `mix compile` clean, mock path returns valid pid
- **Committed in:** `5c079b5` (Task 1 commit)

**2. [Rule 2 - Missing Critical] AudioBuffer nil guard in handle_cast :finish**
- **Found during:** Task 1 (DeepgramStream GenServer implementation)
- **Issue:** Mock mode `State` has `buffer: nil`; calling `AudioBuffer.flush(state.buffer)` in `handle_cast :finish` would crash with a nil match error
- **Fix:** Added `if state.buffer` guard before `AudioBuffer.flush` call in `handle_cast :finish`
- **Files modified:** `lib/livekit/agents/stt/deepgram_stream.ex`
- **Verification:** `mix credo --strict` passes, pattern match safe
- **Committed in:** `5c079b5` (Task 1 commit)

**3. [Rule 2 - Missing Critical] Added catch-all handle_info clause**
- **Found during:** Task 1 (DeepgramStream GenServer implementation)
- **Issue:** Without a catch-all, unexpected Gun protocol messages (e.g., `:gun_error`, `:gun_tunnel_up`) would log a GenServer unhandled message warning and potentially crash
- **Fix:** Added `def handle_info(_msg, state), do: {:noreply, state}` catch-all
- **Files modified:** `lib/livekit/agents/stt/deepgram_stream.ex`
- **Verification:** `mix credo --strict` passes with no issues
- **Committed in:** `5c079b5` (Task 1 commit)

---

**Total deviations:** 3 auto-fixed (1 bug fix, 2 missing critical)
**Impact on plan:** All fixes necessary for correctness. No scope creep.

## Issues Encountered

- `mix clean` deleted compiled proto `.pb.ex` artifacts causing compile failures. Resolved by running `git checkout HEAD -- lib/livekit/proto/` to restore the tracked generated files. Pre-existing issue with proto compilation ordering after a clean build.

## User Setup Required

None - no external service configuration required. Mock mode works without an API key.

## Next Phase Readiness

- Full STT behaviour contract is now implemented: `transcribe/2` (batch HTTP) and `stream/1` (WebSocket streaming) are both available on `Livekit.Agents.STT.Deepgram`
- Phase 7 (Voice Pipeline) can call `stream/1` to get a persistent streaming transcription process
- `DeepgramStream.send_audio/2` and `DeepgramStream.finish/1` are the client-facing API for audio input and graceful shutdown
- Real WebSocket connection requires `DEEPGRAM_API_KEY` at runtime; mock mode works in CI without keys

---
*Phase: 04-deepgram-stt*
*Completed: 2026-04-14*

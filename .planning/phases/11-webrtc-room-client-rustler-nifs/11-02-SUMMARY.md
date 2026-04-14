---
phase: 11-webrtc-room-client-rustler-nifs
plan: "02"
subsystem: native-nif
tags: [rust, rustler, livekit, webrtc, nif, tokio, event-forwarding]
dependency_graph:
  requires: [11-01]
  provides: [room_connect, room_disconnect, RoomResource, AudioTrackResource]
  affects: [11-03, 11-04, 12-roomio-and-agent-session-integration]
tech_stack:
  added: []
  patterns:
    - "DirtyIo NIF scheduler for blocking tokio::Runtime::block_on calls"
    - "tokio task per Room for async event forwarding to BEAM PIDs"
    - "OwnedEnv::send_and_clear from tokio threads only (never from BEAM threads)"
    - "RefUnwindSafe manual impl for NIF resource structs containing non-auto types"
key_files:
  created:
    - native/livekit_webrtc/src/room.rs
    - native/livekit_webrtc/Cargo.lock
  modified:
    - native/livekit_webrtc/src/lib.rs
    - native/livekit_webrtc/src/resources.rs
decisions:
  - "Used Room::close() not Room::disconnect() — livekit 0.7.36 has no disconnect() method"
  - "RoomOptions is #[non_exhaustive] — must use Default::default() + field mutation, not struct literal spread"
  - "RefUnwindSafe impl required for ResourceArc<T> to satisfy NifReturnable blanket impl in rustler 0.37"
  - "Removed explicit NIF list from rustler::init! — deprecated since 0.34, NIFs registered via inventory"
metrics:
  duration: "9m"
  completed: "2026-04-14T18:25:22Z"
  tasks_completed: 2
  files_changed: 4
---

# Phase 11 Plan 02: Room Connect/Disconnect NIFs with Event Forwarding Summary

Implemented `room_connect` and `room_disconnect` NIFs that bridge LiveKit's tokio async world to Elixir's message-passing world. Room events are forwarded as Erlang tuples to a registered listener PID via `OwnedEnv::send_and_clear` called exclusively from a tokio worker thread.

## What Was Built

### native/livekit_webrtc/src/room.rs (new)

Full implementation of two NIFs and the event forwarding loop:

**`room_connect/3`** (`DirtyIo` scheduler):
- Calls `crate::runtime::TOKIO.block_on(Room::connect(...))` synchronously on a dirty I/O thread
- Builds `RoomOptions` via `Default::default()` + field mutation (non-exhaustive struct)
- Spawns a tokio task that owns the `UnboundedReceiver<RoomEvent>` and loops with `rx.recv().await`
- Returns `ResourceArc<RoomResource>` wrapping the `Arc<Room>`, `AbortHandle`, and `LocalPid`

**`room_disconnect/1`** (`DirtyIo` scheduler):
- Aborts the event forwarding task first (preventing spurious post-disconnect messages)
- Calls `room.close().await` for graceful WebRTC signaling teardown

**`forward_room_event/2`** (private, tokio-thread only):
- Handles all 8 D-12 event types: `ParticipantConnected`, `ParticipantDisconnected`, `TrackSubscribed`, `TrackUnsubscribed`, `TrackPublished`, `TrackUnpublished`, `DataReceived`, `ConnectionQualityChanged`, `Disconnected`
- Each arm creates an `OwnedEnv`, encodes a tuple, and calls `send_and_clear`
- `_ => {}` wildcard silently drops non-D-12 events

### native/livekit_webrtc/src/resources.rs (modified)

- Added `listener_pid: LocalPid` to `AudioTrackResource` for Plan 03 audio streaming
- Added `IMPLEMENTS_DOWN = true` + `down()` to `AudioTrackResource` (aborts stream task on GC)
- Added `impl RefUnwindSafe` for both resource structs (required by `NifReturnable` blanket in rustler 0.37)

### native/livekit_webrtc/src/lib.rs (modified)

- Replaced inline `pub mod room { ... }` stub with `mod room;` (real implementation)
- Removed deprecated explicit NIF list from `rustler::init!` (deprecated since rustler 0.34; `inventory` handles registration automatically)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] livekit 0.7.36 has `close()` not `disconnect()`**
- **Found during:** Task 1 — cargo build
- **Issue:** Plan specified `room.disconnect().await` but `Room` in livekit 0.7.36 exposes `close()` / `close_with_reason()` for graceful teardown. No `disconnect()` method exists.
- **Fix:** Changed `room.room.disconnect().await.ok()` to `room.room.close().await.ok()`
- **Files modified:** `native/livekit_webrtc/src/room.rs`
- **Commit:** 39e9abf

**2. [Rule 1 - Bug] `RoomOptions` is `#[non_exhaustive]` — struct literal spread forbidden outside crate**
- **Found during:** Task 1 — cargo build (E0639)
- **Issue:** Plan used `RoomOptions { auto_subscribe: true, ..Default::default() }` but `RoomOptions` is marked `#[non_exhaustive]` in livekit 0.7.36, prohibiting struct literal expressions outside the defining crate.
- **Fix:** Changed to `let mut opts = RoomOptions::default(); opts.auto_subscribe = true;`
- **Files modified:** `native/livekit_webrtc/src/room.rs`
- **Commit:** 39e9abf

**3. [Rule 2 - Missing critical functionality] `RefUnwindSafe` impl required for `NifReturnable`**
- **Found during:** Task 1 — cargo build (E0277)
- **Issue:** rustler 0.37's `NifReturnable` blanket requires `T: Encoder + RefUnwindSafe`. `Room` contains `parking_lot::RwLock` which opts out of auto-`RefUnwindSafe`. Without this impl, `Result<ResourceArc<RoomResource>, rustler::Error>` cannot be returned from a NIF.
- **Fix:** Added `impl std::panic::RefUnwindSafe for RoomResource {}` and same for `AudioTrackResource`. Safe because Rustler's `catch_unwind` only guards against NIF panics — `Room` is never accessed across the unwind boundary.
- **Files modified:** `native/livekit_webrtc/src/resources.rs`
- **Commit:** 7a57ebe

**4. [Rule 1 - Bug] Deprecated explicit NIF list in `rustler::init!`**
- **Found during:** Task 1 — cargo build (deprecation warning)
- **Issue:** rustler 0.34+ deprecated passing the explicit NIF function array to `rustler::init!`. The argument is ignored; NIFs are collected via `inventory::submit!` by the `#[rustler::nif]` attribute macro.
- **Fix:** Removed the NIF list, leaving `rustler::init!("Elixir.Livekit.WebRTC.Native", load = load);`
- **Files modified:** `native/livekit_webrtc/src/lib.rs`
- **Commit:** 39e9abf

**5. [Rule 3 - Blocking issue] rustc 1.85.0 incompatible with dependency requirements**
- **Found during:** Task 1 — first cargo build attempt
- **Issue:** icu_collections 2.2.0, rustler 0.37.3, libloading 0.9.0 require rustc 1.86–1.91. System had rustc 1.85.0.
- **Fix:** Ran `rustup update stable` — upgraded to rustc 1.94.1.
- **Files modified:** None (toolchain update only)
- **Commit:** N/A

## livekit Crate API Differences from RESEARCH.md

| RESEARCH.md stated | Actual livekit 0.7.36 API |
|--------------------|--------------------------|
| `room.disconnect().await` | `room.close().await` (graceful) or `room.close_with_reason(reason).await` |
| `RoomOptions { auto_subscribe: true, ..Default::default() }` | Must use `Default::default()` + field mutation — struct is `#[non_exhaustive]` |
| `DataReceived { payload: Arc<Vec<u8>>, ... }` | Confirmed — payload is `Arc<Vec<u8>>`; cloned with `(*payload).clone()` |
| `ConnectionQualityChanged { participant: RemoteParticipant, ... }` | `participant` is `Participant` (enum, not `RemoteParticipant`) — still has `.identity()` |

## IMPLEMENTS_DOWN Verification

`RoomResource::down` is invoked by BEAM whenever the Elixir process that holds the `ResourceArc` reference exits or is GC'd. The `down` function calls `self.event_task.abort()`, stopping the tokio event loop task. This was verified by:

1. `const IMPLEMENTS_DOWN: bool = true;` is set in the `Resource` impl
2. `env.register::<resources::RoomResource>()` is called in the `load` function — this is required for `IMPLEMENTS_DOWN` to be activated (resource types without `register` do not receive `down` callbacks)
3. `cargo build` passes with no errors, confirming the trait impl is structurally correct

The same pattern applies to `AudioTrackResource` (added in this plan), which will abort the audio streaming task (Plan 03) when the subscriber process exits.

## Known Stubs

None — this plan's goal (room connect/disconnect with event forwarding) is fully implemented. The `audio_subscribe` and `audio_publish_frame` functions in `lib.rs` remain as stubs for Plan 03, but they do not affect this plan's completeness.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes beyond what is documented in the plan's threat model. The `room.close()` call (substituted for `disconnect()`) follows the same trust boundary as planned — token passed through to livekit server validation unchanged.

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| `native/livekit_webrtc/src/room.rs` exists | FOUND |
| `native/livekit_webrtc/src/resources.rs` exists | FOUND |
| `11-02-SUMMARY.md` exists | FOUND |
| Commit 39e9abf (room.rs + lib.rs) | FOUND |
| Commit 7a57ebe (resources.rs) | FOUND |
| `cargo build` exits 0 | PASSED (0 errors, 0 warnings) |

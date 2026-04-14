---
phase: 11-webrtc-room-client-rustler-nifs
plan: "03"
subsystem: webrtc-nif-audio
tags: [rust, rustler, nif, audio, tokio, livekit, pcm]
dependency_graph:
  requires: [native/livekit_webrtc/src/resources.rs, native/livekit_webrtc/src/runtime.rs, native/livekit_webrtc/src/atoms.rs]
  provides: [native/livekit_webrtc/src/audio.rs]
  affects: [native/livekit_webrtc/src/lib.rs, native/livekit_webrtc/src/resources.rs]
tech_stack:
  added: []
  patterns: [NativeAudioStream::with_options for bounded queue, OwnedEnv::send_and_clear from tokio task, tokio::time::timeout guarding capture_frame]
key_files:
  created:
    - native/livekit_webrtc/src/audio.rs
  modified:
    - native/livekit_webrtc/src/lib.rs
    - native/livekit_webrtc/src/resources.rs
    - .gitignore
decisions:
  - "NativeAudioStream::with_options used (not ::new) — public ::new only takes 3 args; queue_size via NativeAudioStreamOptions"
  - "rustler::init! explicit NIF list removed — deprecated since 0.34, NIFs collected via inventory in 0.37"
  - "RefUnwindSafe impl added to RoomResource and AudioTrackResource — required by rustler 0.37 NifReturnable bound on ResourceArc"
  - "priv/native/ and native/livekit_webrtc/target/ added to .gitignore — compiled NIF artifacts are not source"
metrics:
  duration: "~15 minutes"
  completed: "2026-04-14"
  tasks_completed: 2
  files_created: 2
  files_modified: 3
---

# Phase 11 Plan 03: Audio Subscribe/Publish NIFs Summary

Implemented `audio_subscribe` and `audio_publish_frame` NIFs in `native/livekit_webrtc/src/audio.rs` — streaming LE int16 PCM audio frames to Elixir PIDs and publishing synthesized audio back to the LiveKit room with a 500ms timeout guard on `capture_frame`.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Implement audio_subscribe and audio_publish_frame NIFs | 88732ac | audio.rs, lib.rs, resources.rs, Cargo.lock |
| 2 | mix compile verification and NIF artifact check | 64efa4f | .gitignore |

## API Findings vs RESEARCH.md

### NativeAudioStream::new Signature (RESEARCH.md Assumption A2 — INCORRECT)

**RESEARCH.md assumed:** `NativeAudioStream::new(audio_track, sample_rate: i32, num_channels: i32, queue_size_frames: Option<usize>)`

**Actual public API (libwebrtc 0.3.29):**
```rust
// Public wrapper — only 3 args
NativeAudioStream::new(audio_track: RtcAudioTrack, sample_rate: i32, num_channels: i32) -> Self

// For custom queue size, use:
NativeAudioStream::with_options(
    audio_track: RtcAudioTrack,
    sample_rate: i32,
    num_channels: i32,
    options: NativeAudioStreamOptions,  // { queue_size_frames: Option<usize> }
) -> Self
```

The 4-arg signature in RESEARCH.md matches the private `imp::NativeAudioStream::new` (used internally by the wrapper). The public API uses `with_options` for custom queue sizes. **Fix applied:** used `NativeAudioStream::with_options` with `NativeAudioStreamOptions { queue_size_frames: Some(480) }`.

### NativeAudioSource::new Signature — CORRECT

```rust
// Matches RESEARCH.md exactly:
NativeAudioSource::new(
    options: AudioSourceOptions,
    sample_rate: u32,
    num_channels: u32,
    queue_size_ms: u32,  // must be multiple of 10
) -> NativeAudioSource
```

### capture_frame Signature — CORRECT

```rust
pub async fn capture_frame(&self, frame: &AudioFrame<'_>) -> Result<(), RtcError>
```

The blocking behavior (RESEARCH.md Pitfall 2) is confirmed: the buffered path awaits a `oneshot::Receiver<()>` that the C++ side resolves via callback. If the callback is never called, `capture_frame` hangs. The 500ms `tokio::time::timeout` guard is correctly placed.

### frame.data Type — CONFIRMED

`frame.data` is `Cow<[i16]>` (verified in libwebrtc source: `AudioFrame { data: Cow<'a, [i16]>, ... }`). The conversion `frame.data.iter().flat_map(|s| s.to_le_bytes()).collect::<Vec<u8>>()` is correct.

### NativeAudioSource Import Path — CORRECTED

**Plan assumed:** `livekit::webrtc::native::audio_source::NativeAudioSource`

**Actual path:** `livekit::webrtc::audio_source::native::NativeAudioSource`

(`livekit::webrtc` re-exports `libwebrtc::*`; `libwebrtc` has `pub mod audio_source` at top level with `pub mod native` inside it.)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] NativeAudioStream::new signature mismatch**
- **Found during:** Task 1 (cargo build)
- **Issue:** Plan code called `NativeAudioStream::new(rtc_track, TARGET_SAMPLE_RATE, TARGET_CHANNELS, Some(QUEUE_SIZE_FRAMES))` — 4 args. Public API only accepts 3.
- **Fix:** Used `NativeAudioStream::with_options(rtc_track, TARGET_SAMPLE_RATE, TARGET_CHANNELS, NativeAudioStreamOptions { queue_size_frames: Some(QUEUE_SIZE_FRAMES) })`
- **Files modified:** native/livekit_webrtc/src/audio.rs
- **Commit:** 88732ac

**2. [Rule 1 - Bug] NativeAudioSource import path wrong**
- **Found during:** Task 1 (cargo build E0432)
- **Issue:** `livekit::webrtc::native::audio_source::NativeAudioSource` — `native` module in libwebrtc only re-exports `apm`, `audio_mixer`, `audio_resampler`, `frame_cryptor`, `yuv_helper`; not `audio_source`.
- **Fix:** Corrected to `livekit::webrtc::audio_source::native::NativeAudioSource`
- **Files modified:** native/livekit_webrtc/src/audio.rs
- **Commit:** 88732ac

**3. [Rule 2 - Missing critical functionality] RefUnwindSafe required for ResourceArc in rustler 0.37**
- **Found during:** Task 1 (cargo build E0277)
- **Issue:** `rustler::codegen_runtime::NifReturnable` is blanket-impl'd for `T: Encoder + RefUnwindSafe`. `RoomResource` wraps `Arc<Room>` whose `Room` struct contains a `Dispatcher<RoomEvent>` that doesn't auto-impl `RefUnwindSafe`. This caused E0277 on both `room_connect` and `audio_subscribe` stubs. The Plan 01 SUMMARY claimed successful compilation but the error existed in the cherry-picked code.
- **Fix:** Added `impl std::panic::RefUnwindSafe for RoomResource {}` and `impl std::panic::RefUnwindSafe for AudioTrackResource {}` with safety comments.
- **Files modified:** native/livekit_webrtc/src/resources.rs
- **Commit:** 88732ac

**4. [Rule 1 - Bug] rustler::init! deprecated explicit NIF list caused warning**
- **Found during:** Task 1 (cargo build warning)
- **Issue:** Passing `[room_connect, room_disconnect, audio_subscribe, audio_publish_frame]` to `rustler::init!` is deprecated since rustler 0.34 — NIFs are auto-collected via `inventory` when using `#[rustler::nif]`.
- **Fix:** Removed the explicit list, changed to `rustler::init!("Elixir.Livekit.WebRTC.Native", load = load)`
- **Files modified:** native/livekit_webrtc/src/lib.rs
- **Commit:** 88732ac

**5. [Rule 2 - Missing critical functionality] Build artifacts not gitignored**
- **Found during:** Task 2 (git status after mix compile)
- **Issue:** `priv/native/` (NIF .so) and `native/livekit_webrtc/target/` (Rust build cache) were untracked, not gitignored.
- **Fix:** Added both paths to `.gitignore`
- **Files modified:** .gitignore
- **Commit:** 64efa4f

## Known Stubs

None — both NIFs are fully implemented (not stubbed). The `room_connect` and `room_disconnect` NIFs remain as stubs (raise `:not_implemented`) — this is intentional and tracked for Plan 02.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. The `audio_subscribe` and `audio_publish_frame` NIFs use the existing `RoomResource` trust boundary documented in the plan's threat model. All mitigations (T-11-10 through T-11-12) are implemented as specified.

## Self-Check

- FOUND: native/livekit_webrtc/src/audio.rs
- FOUND: .planning/phases/11-webrtc-room-client-rustler-nifs/11-03-SUMMARY.md
- FOUND: commit 88732ac (feat: audio NIFs)
- FOUND: commit 64efa4f (chore: gitignore artifacts)

**Result: PASSED**

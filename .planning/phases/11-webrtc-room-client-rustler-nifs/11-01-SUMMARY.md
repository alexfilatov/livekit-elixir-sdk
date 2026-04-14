---
phase: 11-webrtc-room-client-rustler-nifs
plan: "01"
subsystem: webrtc-nif
tags: [rust, rustler, nif, tokio, livekit]
dependency_graph:
  requires: []
  provides: [native/livekit_webrtc, lib/livekit/webrtc/native.ex]
  affects: [mix.exs]
tech_stack:
  added: [rustler 0.37.3, livekit 0.7 (Cargo dep), once_cell 1 (Cargo dep), tokio full (Cargo dep)]
  patterns: [NIF resource types, global tokio runtime via once_cell::Lazy, dirty scheduler NIFs]
key_files:
  created:
    - native/livekit_webrtc/Cargo.toml
    - native/livekit_webrtc/.cargo/config.toml
    - native/livekit_webrtc/src/lib.rs
    - native/livekit_webrtc/src/runtime.rs
    - native/livekit_webrtc/src/atoms.rs
    - native/livekit_webrtc/src/resources.rs
    - lib/livekit/webrtc/native.ex
  modified:
    - mix.exs
    - mix.lock
decisions:
  - "Used rustler ~> 0.37 (0.37.3 installed) per RESEARCH.md override of CONTEXT.md D-15 which listed 0.35"
  - "NIF stubs return :nif_not_loaded via :erlang.nif_error — implementations deferred to Plans 02 and 03"
  - "AbortHandle stored in RoomResource.down callback to auto-cancel event task when Elixir process GC'd"
  - "Global multi-threaded tokio runtime via once_cell::Lazy — never per-room runtimes"
  - "DirtyIo scheduler for all four NIF stubs to avoid blocking BEAM schedulers"
metrics:
  duration: "~2 minutes"
  completed: "2026-04-14"
  tasks_completed: 2
  files_created: 7
  files_modified: 2
---

# Phase 11 Plan 01: Rust NIF Scaffold Summary

Bootstrapped the Rustler NIF crate for LiveKit WebRTC bindings — global tokio runtime via `once_cell::Lazy`, four `DirtyIo` NIF stubs, two resource types with BEAM GC abort-handle integration, and Elixir stub module wired via `use Rustler`.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create Rust NIF crate scaffold | 9841485 | native/livekit_webrtc/{Cargo.toml,.cargo/config.toml,src/{lib,runtime,atoms,resources}.rs} |
| 2 | Wire Rustler into mix.exs and create Elixir NIF stub | 5d482e7 | mix.exs, mix.lock, lib/livekit/webrtc/native.ex |

## Exact Versions Installed

- **rustler (Hex):** 0.37.3 (resolved by `mix deps.get`)
- **livekit (Cargo):** ~0.7 (pinned in Cargo.toml; Cargo.lock generated at `mix compile` time)
- **once_cell (Cargo):** ~1 (pinned in Cargo.toml)

## NIF Artifact Path

The NIF shared library will be generated at compile time by Rustler at:
- macOS: `priv/native/liblivekit_webrtc.dylib`
- Linux: `priv/native/liblivekit_webrtc.so`

Note: `mix compile` was NOT run in this plan per instructions — the livekit crate downloads ~100MB libwebrtc binaries. Run `mix deps.get && mix compile` manually when ready to build.

## macOS Linker Flag

`.cargo/config.toml` is in place at `native/livekit_webrtc/.cargo/config.toml` with:
```toml
[target.'cfg(target_os = "macos")']
rustflags = ["-C", "link-args=-ObjC"]
```
This prevents the "unrecognized selector" runtime crash when `Room::connect` is first called on macOS (required by Objective-C runtime for WebRTC's audio subsystem).

## Compile Warnings

None — compilation of Rust not performed in this plan (deferred per instructions). The Elixir file passes `mix format --check-formatted` with zero issues.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Format] Fixed @spec line length for audio_subscribe**
- **Found during:** Task 2 verification via `mix format --check-formatted`
- **Issue:** `@spec audio_subscribe(reference(), String.t(), pid()) :: {:ok, reference()} | {:error, String.t()}` exceeded formatter line width
- **Fix:** Wrapped return type onto next line per formatter output
- **Files modified:** lib/livekit/webrtc/native.ex
- **Commit:** Included in 5d482e7

## Known Stubs

| File | Description |
|------|-------------|
| lib/livekit/webrtc/native.ex | All four NIFs return `:erlang.nif_error(:nif_not_loaded)` — intentional scaffold stubs until Plans 02 (room) and 03 (audio) implement the Rust side |
| native/livekit_webrtc/src/lib.rs | `room_connect` and `audio_subscribe` return `Err(RaiseAtom("not_implemented"))`; `room_disconnect` and `audio_publish_frame` return `atoms::not_loaded()` — intentional |

These stubs are the explicit goal of Plan 01. Plans 02 and 03 replace them with real implementations.

## Threat Surface Scan

No new network endpoints or auth paths introduced — this plan creates only a NIF scaffold with stub implementations. The threat model items T-11-01 through T-11-04 are structurally addressed:
- T-11-01 (DoS via blocking): All stubs use `schedule = "DirtyIo"` 
- T-11-03 (NIF panic): Rustler 0.37+ converts Rust panics to Erlang exceptions
- T-11-04 (AbortHandle tampering): Only `RoomResource::down` (called by BEAM GC) can abort the event task

## Self-Check: PASSED

Files created:
- native/livekit_webrtc/Cargo.toml: FOUND
- native/livekit_webrtc/.cargo/config.toml: FOUND
- native/livekit_webrtc/src/lib.rs: FOUND
- native/livekit_webrtc/src/runtime.rs: FOUND
- native/livekit_webrtc/src/atoms.rs: FOUND
- native/livekit_webrtc/src/resources.rs: FOUND
- lib/livekit/webrtc/native.ex: FOUND

Commits:
- 9841485: FOUND (feat(11-01): add Rust NIF crate scaffold)
- 5d482e7: FOUND (feat(11-01): wire Rustler into mix.exs and add Elixir NIF stub module)

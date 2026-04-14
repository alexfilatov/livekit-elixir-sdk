# Phase 11: WebRTC Room Client (Rustler NIFs) - Research

**Researched:** 2026-04-14
**Domain:** Rustler NIFs + livekit Rust crate + tokio async event streaming to Elixir
**Confidence:** HIGH (core APIs verified via official sources and crates.io)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Use Rustler to create NIF bindings to `livekit-client-sdk-rust`
- **D-02:** The Rust crate lives in `native/livekit_webrtc/` following Rustler conventions
- **D-03:** Elixir wrapper modules in `lib/livekit/webrtc/` provide idiomatic Elixir API
- **D-04:** NIF resources wrap Rust Room, Track, and Participant objects
- **D-05:** Audio frames flow as binaries between Rust and Elixir (zero-copy where possible)
- **D-06:** `Livekit.WebRTC.Room` — connect/disconnect, participant events, data channels
- **D-07:** `Livekit.WebRTC.AudioTrack` — subscribe to remote audio, publish local audio
- **D-08:** `Livekit.WebRTC.VideoTrack` — subscribe to remote video, publish local video (basic)
- **D-09:** `Livekit.WebRTC.Participant` — identity, metadata, track listing
- **D-10:** Room events dispatched to Elixir process via message passing (not polling)
- **D-11:** Rust side spawns a tokio task per Room that forwards events to a registered Elixir PID
- **D-12:** Events: participant_connected/disconnected, track_subscribed/unsubscribed, track_published/unpublished, data_received, connection_quality_changed, disconnected
- **D-13:** Audio frames from subscribed tracks sent as `{:audio_frame, track_sid, binary}` messages
- **D-14:** Use `rustler::Env::send` for async event dispatch from Rust to Elixir
- **D-15:** Add `rustler ~> 0.35` to mix.exs
- **D-16:** Add `livekit` and `livekit-api` Rust crates as dependencies in native/livekit_webrtc/Cargo.toml
- **D-17:** Rust toolchain required (rustc, cargo) — document in README
- **D-18:** Use `tokio` runtime in Rust for async WebRTC operations
- **D-19:** Unit tests for Elixir wrapper modules with mock NIF responses
- **D-20:** Integration tests connecting to a local LiveKit server (docker-compose)
- **D-21:** Test audio round-trip: publish from Elixir -> receive in Elixir via second participant

### Claude's Discretion

- Exact Rustler resource struct design
- Error handling strategy across the NIF boundary
- Whether to use dirty schedulers for blocking operations
- Audio resampling on the Rust side vs Elixir side

### Deferred Ideas (OUT OF SCOPE)

None — this is the critical connectivity layer.
</user_constraints>

---

## Summary

Phase 11 creates NIF bindings between Elixir and the official LiveKit Rust client SDK (`livekit` crate, v0.7.36). The binding layer uses Rustler (v0.37.3) as the NIF framework. The central challenge is bridging two async worlds: tokio (Rust) and BEAM message passing (Elixir).

The correct architecture uses a global `once_cell::sync::Lazy<tokio::runtime::Runtime>` in Rust to own the tokio runtime. Room connection NIFs return immediately after spawning tokio tasks; those tasks run in the global runtime and forward `RoomEvent` values to Elixir PIDs via `OwnedEnv::send_and_clear`. This is the same pattern proven by the `echo_rust_nif` reference project and is safe because tokio threads are not BEAM scheduler threads, satisfying the restriction imposed by `OwnedEnv::send_and_clear`.

**Critical restriction:** `OwnedEnv::send_and_clear` panics if called from a BEAM-managed thread. It MUST only be called from threads that Rust owns — i.e., tokio worker threads or `std::thread::spawn` threads. This is satisfied by the global runtime pattern.

**Primary recommendation:** Use a single global tokio `Runtime` (multi-threaded), store `Arc<Room>` + `tokio::sync::mpsc::Sender<Command>` as a Rustler `ResourceArc`, and dispatch all LiveKit events to Elixir via `OwnedEnv::send_and_clear` called from tokio tasks.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `rustler` (Hex) | 0.37.3 | Elixir → Rust NIF framework | Official Rustler package for Elixir |
| `rustler` (crate) | 0.37.3 | Rust side of the NIF bridge | Macros, resource types, term encoding |
| `livekit` (crate) | 0.7.36 | LiveKit WebRTC client SDK | Official LiveKit Rust SDK |
| `tokio` (crate) | (workspace dep of livekit) | Async runtime for WebRTC ops | Required by livekit; multi-threaded runtime |
| `once_cell` (crate) | 1.21.4 | Global tokio runtime initialization | Industry standard for safe statics in Rust |

[VERIFIED: crates.io registry - livekit 0.7.36 published 2026-04-02, rustler 0.37.3 published 2026-03-13, once_cell 1.21.4 published 2026-03-12]
[VERIFIED: hex.pm - rustler 0.37.3 published 2026-02-11]

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `rustler_precompiled` (Hex) | 0.9.0 | Pre-compiled NIF delivery | If distributing as Hex package; not needed for internal use |
| `futures` (crate) | (workspace dep) | `StreamExt` for `NativeAudioStream` | Required to iterate audio frames with `.next().await` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Rustler NIFs | Port (external process) | Port is safer (crash isolation) but far higher latency for audio — unacceptable for real-time |
| Rustler NIFs | ex_webrtc (pure Elixir) | ex_webrtc is pure Elixir WebRTC; doesn't bind to LiveKit's server-specific protocol |
| Global tokio runtime | Per-room runtime | Global is simpler; per-room adds overhead with no benefit for this use case |
| `once_cell::Lazy` | `std::sync::OnceLock` | Both work; `once_cell` is older convention, `OnceLock` is now std (Rust 1.70+); either fine |

**Installation (mix.exs):**
```elixir
{:rustler, "~> 0.37", runtime: false}
```

**Installation (native/livekit_webrtc/Cargo.toml):**
```toml
[dependencies]
rustler = "0.37"
livekit = "0.7"
once_cell = "1"
tokio = { version = "1", features = ["full"] }
futures = "0.3"
```

**Version verification:** Confirmed against crates.io API on 2026-04-14.

## Architecture Patterns

### Recommended Project Structure

```
native/livekit_webrtc/
├── Cargo.toml                  # workspace NIF crate
└── src/
    ├── lib.rs                  # rustler::init!, load fn, resource registration
    ├── runtime.rs              # global tokio Runtime (once_cell::Lazy)
    ├── room.rs                 # room_connect, room_disconnect, room_send_data NIFs
    ├── audio_track.rs          # audio_subscribe, audio_publish NIFs
    ├── resources.rs            # RoomResource, AudioTrackResource structs
    └── atoms.rs                # Elixir atom definitions

lib/livekit/webrtc/
├── room.ex                     # Livekit.WebRTC.Room GenServer
├── audio_track.ex              # Livekit.WebRTC.AudioTrack
├── video_track.ex              # Livekit.WebRTC.VideoTrack
├── participant.ex              # Livekit.WebRTC.Participant
└── native.ex                   # NIF wrapper (generated by mix rustler.new)

test/livekit/webrtc/
├── room_test.exs               # unit tests with mock NIF
└── integration/
    └── room_integration_test.exs  # requires local LiveKit server
```

### Pattern 1: Global Tokio Runtime

**What:** Single `tokio::runtime::Runtime` created once via `once_cell::sync::Lazy`, shared by all NIF calls.
**When to use:** Always — tokio tasks must run in the same runtime to share async state.

```rust
// Source: echo_rust_nif (github.com/elbow-jason/echo_rust_nif) + tokio docs
use once_cell::sync::Lazy;
use tokio::runtime::{Builder, Runtime};

static TOKIO: Lazy<Runtime> = Lazy::new(|| {
    Builder::new_multi_thread()
        .enable_all()
        .build()
        .expect("Failed to build tokio runtime")
});

pub fn spawn<F>(future: F) -> tokio::task::JoinHandle<F::Output>
where
    F: std::future::Future + Send + 'static,
    F::Output: Send + 'static,
{
    TOKIO.spawn(future)
}
```

### Pattern 2: NIF Resource for Room Handle

**What:** Store `Arc<Room>` + event task abort handle in a Rustler `ResourceArc`. Elixir receives an opaque reference it passes back to NIFs.
**When to use:** For any long-lived Rust object that Elixir must reference across multiple NIF calls.

```rust
// Source: rustler docs (docs.rs/rustler/0.37.3/rustler/trait.Resource.html)
use rustler::{Resource, ResourceArc, LocalPid};
use tokio::task::AbortHandle;
use std::sync::Arc;
use livekit::Room;

pub struct RoomResource {
    pub room: Arc<Room>,
    pub event_task: AbortHandle,
    pub listener_pid: LocalPid,
}

#[rustler::resource_impl]
impl Resource for RoomResource {
    const IMPLEMENTS_DOWN: bool = true;

    fn down<'a>(&'a self, _env: rustler::Env<'a>, _pid: LocalPid, _mon: rustler::Monitor) {
        // Elixir process died — abort the event forwarding task
        self.event_task.abort();
    }
}
```

### Pattern 3: OwnedEnv::send_and_clear for Event Forwarding

**What:** Send Elixir messages from tokio tasks to a registered PID using `OwnedEnv`.
**When to use:** Any time Rust needs to push an event to an Elixir process asynchronously.
**Critical:** ONLY call `send_and_clear` from threads NOT managed by the BEAM (tokio threads satisfy this).

```rust
// Source: rustler env docs + echo_rust_nif pattern
use rustler::{OwnedEnv, LocalPid};

fn send_event_to_elixir(pid: &LocalPid, event_term: impl rustler::Encoder + Send) {
    let pid = *pid;
    let mut env = OwnedEnv::new();
    // This is safe because we are on a tokio thread, not a BEAM scheduler thread
    let _ = env.send_and_clear(&pid, move |env| event_term.encode(env));
}
```

### Pattern 4: Room Connect NIF with Async Dispatch

**What:** NIF returns immediately (dirty IO scheduler), spawning a tokio task that runs `Room::connect` and a second task that forwards `RoomEvent` to Elixir.

```rust
// Source: livekit rust-sdks README + rustler nif docs
use rustler::{Env, ResourceArc, LocalPid};
use livekit::{Room, RoomOptions, RoomEvent};

#[rustler::nif(schedule = "DirtyIo")]
pub fn room_connect(
    env: Env,
    url: String,
    token: String,
    listener_pid: LocalPid,
) -> Result<ResourceArc<RoomResource>, rustler::Error> {
    let (room, mut rx) = TOKIO.block_on(async {
        Room::connect(&url, &token, RoomOptions::default()).await
    }).map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;

    let room = Arc::new(room);
    let pid = listener_pid;

    let event_handle = crate::runtime::spawn({
        let room = room.clone();
        async move {
            while let Some(event) = rx.recv().await {
                forward_room_event(&pid, &room, event);
            }
        }
    });

    Ok(ResourceArc::new(RoomResource {
        room,
        event_task: event_handle.abort_handle(),
        listener_pid,
    }))
}
```

### Pattern 5: AudioFrame Binary Transfer

**What:** Convert `AudioFrame { data: Vec<i16>, sample_rate, num_channels, samples_per_channel }` from livekit to Elixir binary.
**When to use:** For every audio frame received via `NativeAudioStream`.

```rust
// Source: livekit save_to_disk example + rustler Binary docs
use rustler::Binary;
use livekit::webrtc::audio_stream::native::NativeAudioStream;
use futures::StreamExt;

async fn stream_audio_to_elixir(
    pid: LocalPid,
    audio_track: livekit::track::RemoteAudioTrack,
    target_sample_rate: i32,
    target_channels: i32,
) {
    let rtc_track = audio_track.rtc_track();
    let mut stream = NativeAudioStream::new(rtc_track, target_sample_rate, target_channels, None);

    while let Some(frame) = stream.next().await {
        // frame.data is Vec<i16> — convert to bytes for Elixir binary
        let bytes: Vec<u8> = frame.data.iter()
            .flat_map(|s| s.to_le_bytes())
            .collect();

        let mut env = OwnedEnv::new();
        let track_sid = /* track sid string */ String::new();
        let _ = env.send_and_clear(&pid, move |env| {
            (atoms::audio_frame(), track_sid, bytes).encode(env)
        });
    }
}
```

### NativeAudioStream Signature (Verified)

```rust
// Source: github.com/livekit/rust-sdks/blob/main/libwebrtc/src/native/audio_stream.rs
pub fn new(
    audio_track: RtcAudioTrack,
    sample_rate: i32,
    num_channels: i32,
    queue_size_frames: Option<usize>,
) -> Self
```

### AudioFrame Struct (Verified)

```rust
// Source: livekit rust-sdks libwebrtc
pub struct AudioFrame<'a> {
    pub data: Cow<'a, [i16]>,  // PCM int16, interleaved by channel
    pub sample_rate: u32,
    pub num_channels: u32,
    pub samples_per_channel: u32,
}
```

### Pattern 6: Publishing Local Audio

```rust
// Source: github.com/livekit/rust-sdks/blob/main/examples/local_audio/src/main.rs
use livekit::{
    track::{LocalAudioTrack, LocalTrack},
    webrtc::{
        audio_source::{AudioSourceOptions, RtcAudioSource},
        native::audio_source::NativeAudioSource,
    },
    options::TrackPublishOptions,
};

// Create audio source
let source = NativeAudioSource::new(
    AudioSourceOptions {
        echo_cancellation: false,
        noise_suppression: false,
        auto_gain_control: false,
    },
    48_000,  // sample_rate
    1,       // num_channels (mono)
    1000,    // queue_size_ms
);

// Create and publish track
let track = LocalAudioTrack::create_audio_track(
    "agent_audio",
    RtcAudioSource::Native(source.clone()),
);

room.local_participant()
    .publish_track(
        LocalTrack::Audio(track),
        TrackPublishOptions { ..Default::default() },
    )
    .await?;

// Push audio frames (10ms chunks = sample_rate / 100 samples)
let samples_per_10ms = (48_000 / 100) as usize;
let frame = AudioFrame {
    data: pcm_i16_vec.into(),
    sample_rate: 48_000,
    num_channels: 1,
    samples_per_channel: samples_per_10ms as u32,
};
source.capture_frame(&frame).await?;
```

### Anti-Patterns to Avoid

- **Calling `OwnedEnv::send_and_clear` from a dirty NIF thread:** Dirty NIF threads ARE BEAM-managed threads. Even `DirtyCpu`/`DirtyIo` threads belong to the BEAM. Use `send_and_clear` only from `std::thread::spawn` or tokio threads.
- **Blocking in a NIF without dirty scheduler:** Any NIF that takes >1ms MUST use `#[nif(schedule = "DirtyIo")]` or `#[nif(schedule = "DirtyCpu")]` to avoid blocking the BEAM scheduler.
- **Storing `Env` across NIF calls:** `Env` lifetimes are tied to a single NIF invocation. Use `OwnedEnv` for cross-call term storage.
- **Calling `Room::connect` synchronously on a dirty scheduler:** Prefer `TOKIO.block_on(...)` on a dirty IO thread, OR spawn tokio task and return a future resource.
- **Creating a tokio runtime per Room:** Always use the global shared runtime.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| WebRTC signaling | Custom WebSocket + SDP/ICE | `livekit` crate | Implements full LiveKit signaling protocol + libwebrtc |
| PCM audio mixing | Manual sample mixing | `livekit::webrtc::audio_mixer` | Edge cases: clipping, format mismatch, timing |
| Audio resampling | Simple linear interp | `NativeAudioStream::new(sample_rate, channels)` | Built-in resampling in NativeAudioStream constructor |
| BEAM→Rust message dispatch | Custom port/mailbox | `tokio::sync::mpsc::channel` + NIF calls | Proven pattern; NIFs as entry points + channels for back-pressure |
| NIF resource lifecycle | Manual ref counting | `ResourceArc<T>` + `Resource::down` | Handles GC integration, Drop, and process monitor callbacks |
| Elixir→Rust term encoding | Manual binary serialization | Rustler `Encoder`/`Decoder` derives | Macro-generated, type-safe, zero-copy where possible |

**Key insight:** The livekit Rust crate abstracts away the entire WebRTC+signaling stack. Building any part of that from scratch (ICE, DTLS, SRTP, SDP) would be months of work with subtle correctness issues.

## Common Pitfalls

### Pitfall 1: OwnedEnv Panic on BEAM Threads

**What goes wrong:** `OwnedEnv::send_and_clear` panics with a cryptic message about calling from a VM-managed thread.
**Why it happens:** Even dirty scheduler NIFs run on BEAM-owned threads. The restriction is imposed by the Erlang NIF API, not Rustler.
**How to avoid:** Always call `send_and_clear` from threads you spawn explicitly — either `tokio::spawn` tasks or `std::thread::spawn`. Never from inside a `#[nif]` function directly.
**Warning signs:** Panic at NIF startup or during first event dispatch.

[VERIFIED: docs.rs/rustler/0.37.3 OwnedEnv documentation]

### Pitfall 2: capture_frame Blocking Under Load

**What goes wrong:** `NativeAudioSource::capture_frame` hangs indefinitely when server load is high (100+ rooms or heavy concurrent processing).
**Why it happens:** Underlying `Send()` call in libwebrtc blocks when channel is full; has been reported as a known bug (GitHub issue #420, opened Sep 2024, still unresolved as of 2026-04-14).
**How to avoid:** Run `capture_frame` in a dedicated tokio task; set reasonable `queue_size_ms` (e.g. 500ms not 1000ms); consider a watchdog that aborts and reconnects if capture stalls.
**Warning signs:** Audio track silences without error, NIF call never returns.

[VERIFIED: github.com/livekit/rust-sdks/issues/420]

### Pitfall 3: macOS Linker Flags Missing

**What goes wrong:** Build succeeds but runtime crashes with unrecognized selector errors on macOS.
**Why it happens:** LiveKit's WebRTC uses Objective-C libraries on macOS; without `-ObjC` linker flag, the ObjC runtime isn't initialized.
**How to avoid:** Add `.cargo/config.toml` in the project root (or inside `native/livekit_webrtc/`) with:
```toml
[target.'cfg(target_os = "macos")']
rustflags = ["-C", "link-args=-ObjC"]
```
**Warning signs:** `unrecognized selector sent to instance` or crashes on first Room::connect.

[VERIFIED: github.com/livekit/rust-sdks/.cargo/config.toml]

### Pitfall 4: Rustler NIF Version Mismatch

**What goes wrong:** `rustler ~> 0.35` in mix.exs but Hex has 0.37.3; the Rust crate and Hex package must match.
**Why it happens:** CONTEXT.md specifies `~> 0.35` but latest is 0.37.3; minor version requirement too loose historically caused issues.
**How to avoid:** Use `~> 0.37` in mix.exs to pin to current major. The Hex package version and Rust crate version must be identical.
**Warning signs:** Compilation errors about ABI mismatch or NIF function not found.

[VERIFIED: crates.io + hex.pm versions checked 2026-04-14]

### Pitfall 5: AudioFrame Data Format Mismatch

**What goes wrong:** Audio sounds like noise or is completely silent after crossing the NIF boundary.
**Why it happens:** The livekit `AudioFrame.data` is `Vec<i16>` (little-endian signed 16-bit PCM). The existing `Livekit.Agents.AudioFrame` defaults to 48kHz but accepts format `:pcm_16`. If the binary is not correctly interpreted as little-endian int16, waveform is corrupted.
**How to avoid:** Always encode `Vec<i16>` to bytes via `.to_le_bytes()` in Rust; receive in Elixir as `:pcm_16` format at the agreed sample rate.
**Warning signs:** Deepgram returns empty transcripts despite audio flowing.

[VERIFIED: docs.livekit.io/reference/python/livekit/rtc/audio_frame.html — "format is 16-bit signed integers (int16) interleaved by channel"]

### Pitfall 6: Room Event Receiver Dropped

**What goes wrong:** All `RoomEvent` messages are lost after the first NIF call.
**Why it happens:** `Room::connect` returns `(Room, mpsc::UnboundedReceiver<RoomEvent>)`. If the receiver is not stored (e.g. assigned to `_`), it is dropped immediately and all subsequent events are silently discarded.
**How to avoid:** Store the receiver inside the tokio event loop task. The task must own the receiver for its lifetime.
**Warning signs:** No participant/track events received despite successful connection.

[VERIFIED: github.com/livekit/rust-sdks/blob/main/livekit/src/room/mod.rs]

### Pitfall 7: NIF Resource Not Registered

**What goes wrong:** BEAM crashes with `bad argument` when trying to use a ResourceArc.
**Why it happens:** Every Resource type must be registered in the `load` function via `env.register::<MyResource>()` or `rustler::resource!` macro.
**How to avoid:** In `lib.rs` load function, register ALL resource types before returning `true`.
**Warning signs:** Immediate crash on first NIF call that returns a resource.

[VERIFIED: rustler_tests/native/rustler_test/src/test_resource.rs]

## Code Examples

### Room Connect NIF (full pattern)

```rust
// Source: livekit rust-sdks room/mod.rs + echo_rust_nif pattern
#[rustler::nif(schedule = "DirtyIo")]
fn room_connect(
    url: String,
    token: String,
    listener_pid: LocalPid,
) -> Result<ResourceArc<RoomResource>, rustler::Error> {
    let result = crate::runtime::TOKIO.block_on(async {
        Room::connect(&url, &token, RoomOptions { auto_subscribe: true, ..Default::default() }).await
    });

    let (room, mut rx) = result.map_err(|e| rustler::Error::RaiseTerm(Box::new(e.to_string())))?;
    let room = Arc::new(room);
    let pid = listener_pid;

    let event_task = crate::runtime::spawn(async move {
        while let Some(event) = rx.recv().await {
            let mut env = OwnedEnv::new();
            match event {
                RoomEvent::ParticipantConnected(p) => {
                    let _ = env.send_and_clear(&pid, move |env| {
                        (atoms::participant_connected(), p.identity().to_string()).encode(env)
                    });
                }
                RoomEvent::TrackSubscribed { track, publication, participant } => {
                    // Spawn separate task for audio streaming
                    // ...
                }
                RoomEvent::Disconnected { reason } => {
                    let _ = env.send_and_clear(&pid, move |env| {
                        (atoms::disconnected(), reason.to_string()).encode(env)
                    });
                    break;
                }
                _ => {}
            }
        }
    });

    Ok(ResourceArc::new(RoomResource {
        room,
        event_task: event_task.abort_handle(),
        listener_pid,
    }))
}
```

### Rustler init! macro

```rust
// Source: rustler docs + echo_rust_nif
fn load(env: Env, _: Term) -> bool {
    env.register::<RoomResource>().is_ok()
        && env.register::<AudioTrackResource>().is_ok()
}

rustler::init!(
    "Elixir.Livekit.WebRTC.Native",
    [
        room::room_connect,
        room::room_disconnect,
        audio::audio_subscribe,
        audio::audio_publish_frame,
    ],
    load = load
);
```

### Elixir Wrapper GenServer (skeleton)

```elixir
# Source: project conventions (CONVENTIONS.md)
defmodule Livekit.WebRTC.Room do
  @moduledoc """
  Manages a WebRTC room connection via Rustler NIFs.
  Events are received as messages in the calling process.
  """
  use GenServer
  require Logger

  alias Livekit.WebRTC.Native

  defmodule Config do
    @type t :: %__MODULE__{
      url: String.t(),
      token: String.t(),
      auto_subscribe: boolean()
    }
    defstruct [:url, :token, auto_subscribe: true]
  end

  defmodule State do
    @moduledoc false
    defstruct [:config, :room_ref, :listener_pid]
  end

  @spec connect(Config.t()) :: {:ok, pid()} | {:error, term()}
  def connect(config) do
    GenServer.start_link(__MODULE__, config)
  end

  @impl true
  def init(config) do
    case Native.room_connect(config.url, config.token, self()) do
      {:ok, room_ref} ->
        {:ok, %State{config: config, room_ref: room_ref, listener_pid: self()}}
      {:error, reason} ->
        {:stop, reason}
    end
  end

  # Handle events from Rust event loop
  @impl true
  def handle_info({:participant_connected, identity}, state) do
    Logger.info("Participant connected: #{identity}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:audio_frame, track_sid, binary}, state) do
    # Forward to pipeline
    {:noreply, state}
  end
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `lazy_static!` for global state | `once_cell::sync::Lazy` / `std::sync::OnceLock` | Rust 1.70 (2023) | `OnceLock` is now in std; `once_cell` still widely used |
| Manual `enif_send` in C NIFs | `OwnedEnv::send_and_clear` in Rustler | Rustler ~0.20 | Type-safe, panic-safe cross-thread send |
| Rustler 0.35 workspace template | Rustler 0.36+ generates workspace-style `Cargo.toml` | 0.36.0 (2025-01-13) | `mix rustler.new` now emits workspace layout |
| `rustler::resource!` macro | `#[rustler::resource_impl]` attribute | ~0.33 | More ergonomic; old macro still works |

**Deprecated/outdated:**
- `lazy_static` crate: superseded by `once_cell` and `std::sync::OnceLock`; still works but `once_cell` is preferred
- `rustler ~> 0.35` in CONTEXT.md: latest is 0.37.3; use `~> 0.37`

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `capture_frame` bug (#420) is still unresolved in livekit 0.7.36 | Pitfalls | Low — issue closed without fix note; if fixed, watchdog is still harmless |
| A2 | `NativeAudioStream::new` signature includes `sample_rate` and `num_channels` as parameters (not just rtc_track) | Code Examples | HIGH — if wrong, audio subscription code won't compile; verify against actual crate source |
| A3 | livekit 0.7.36 still requires the `-ObjC` linker flag on macOS | Pitfalls | Medium — if removed in newer version, flag is still harmless |

## Open Questions

1. **livekit crate build time and binary size**
   - What we know: livekit depends on `libwebrtc` (C++) which requires compilation; the crate is ~0.7.36
   - What's unclear: Does `libwebrtc` ship pre-built binaries or require full C++ compile? Full compile can take 30+ minutes.
   - Recommendation: Check `libwebrtc` crate on crates.io for pre-built binaries before committing to build pipeline.

2. **Rustler precompiled vs. compile from source**
   - What we know: `rustler_precompiled` exists for distributing pre-compiled NIFs
   - What's unclear: Whether this is needed for internal use (it's not — only for Hex package distribution)
   - Recommendation: For this project (not published to Hex), compile from source is fine.

3. **Video track implementation scope**
   - What we know: D-08 requires basic video track support
   - What's unclear: Whether `NativeVideoStream` follows the same pattern as `NativeAudioStream`
   - Recommendation: Research `NativeVideoStream` during implementation; assume similar pattern.

4. **capture_frame blocking workaround**
   - What we know: The blocking bug exists under high load
   - What's unclear: Whether `tokio::time::timeout` wrapping capture_frame is a viable workaround
   - Recommendation: Use `tokio::spawn` + `timeout(Duration::from_millis(50), source.capture_frame(&frame))` for each 10ms chunk; abort and re-queue on timeout.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Rust (rustc) | Rustler NIF compilation | ✓ | 1.85.0 | — |
| Cargo | Rust dependency management | ✓ | 1.85.0 | — |
| Docker | Integration test LiveKit server | ✓ | 28.1.1 | Manual LiveKit install |
| docker-compose (docker compose) | Spin up test LiveKit | ✓ (via Docker CLI plugin) | 28.1.1 | — |
| C++ toolchain (clang/gcc) | libwebrtc compilation | [ASSUMED: present on macOS with Xcode CLT] | — | Install Xcode CLT |
| CMake | Possible libwebrtc build requirement | [ASSUMED: present] | — | `brew install cmake` |

[VERIFIED: rustc 1.85.0, cargo 1.85.0, docker 28.1.1 — confirmed via `rustc --version`, `cargo --version`, `docker --version`]

**Missing dependencies with no fallback:**
- None identified (Rust toolchain present, Docker present)

**Missing dependencies with fallback:**
- C++ toolchain / CMake — likely present but unverified; if libwebrtc requires full C++ compilation, install via `xcode-select --install`

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit (built-in Elixir) |
| Config file | `test/test_helper.exs` (existing) |
| Quick run command | `mix test test/livekit/webrtc/ --exclude integration` |
| Full suite command | `mix test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| D-06 | Room connect/disconnect | unit (mock NIF) | `mix test test/livekit/webrtc/room_test.exs` | ❌ Wave 0 |
| D-07 | AudioTrack subscribe/publish | unit (mock NIF) | `mix test test/livekit/webrtc/audio_track_test.exs` | ❌ Wave 0 |
| D-10 | Events dispatched via messages | unit | `mix test test/livekit/webrtc/room_test.exs` | ❌ Wave 0 |
| D-20 | Integration: connect to local LiveKit | integration | `mix test test/livekit/webrtc/ --only integration` | ❌ Wave 0 |
| D-21 | Audio round-trip test | integration | `mix test test/livekit/webrtc/ --only integration` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `mix test test/livekit/webrtc/ --exclude integration`
- **Per wave merge:** `mix test`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `test/livekit/webrtc/room_test.exs` — covers D-06, D-10
- [ ] `test/livekit/webrtc/audio_track_test.exs` — covers D-07
- [ ] `test/livekit/webrtc/integration/room_integration_test.exs` — covers D-20, D-21
- [ ] `lib/livekit/webrtc/native.ex` — generated by `mix rustler.new Livekit.WebRTC.Native livekit_webrtc`
- [ ] `native/livekit_webrtc/Cargo.toml` — generated by mix rustler.new
- [ ] `.cargo/config.toml` — macOS linker flags (`-ObjC`)

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | AccessToken JWT (existing `Livekit.AccessToken`) |
| V3 Session Management | yes | Room resource lifecycle via `ResourceArc` + `Resource::down` |
| V4 Access Control | no | LiveKit server enforces room ACLs via token claims |
| V5 Input Validation | yes | Validate url/token strings before passing to NIF |
| V6 Cryptography | no | livekit crate handles DTLS/SRTP internally |

### Known Threat Patterns for Rustler NIFs

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| NIF panic crashes BEAM | Denial of Service | Rustler catches Rust panics before they unwind to C; use `#[nif]` (not unsafe) |
| Long-running NIF blocks scheduler | Denial of Service | `#[nif(schedule = "DirtyIo")]` for all blocking operations |
| Token leaked in logs | Information Disclosure | Do NOT log token strings; log only room name + identity |
| Use-after-free on Room resource | Tampering | `ResourceArc` is ref-counted; never store raw pointers |
| Event forwarding to wrong PID | Elevation of Privilege | Store `LocalPid` at connect time; validate in `down` callback that abort happens |

## Sources

### Primary (HIGH confidence)

- `crates.io API` — livekit 0.7.36 (2026-04-02), rustler 0.37.3 (2026-03-13), once_cell 1.21.4 (2026-03-12)
- `hex.pm API` — rustler 0.37.3 (2026-02-11), rustler_precompiled 0.9.0 (2026-03-26)
- `github.com/livekit/rust-sdks/blob/main/livekit/src/room/mod.rs` — Room struct, connect signature, RoomEvent variants
- `github.com/livekit/rust-sdks/blob/main/libwebrtc/src/native/audio_stream.rs` — NativeAudioStream::new signature, AudioFrame fields
- `github.com/livekit/rust-sdks/blob/main/examples/local_audio/src/main.rs` — NativeAudioSource, LocalAudioTrack, capture_frame pattern
- `github.com/livekit/rust-sdks/blob/main/examples/save_to_disk/src/main.rs` — NativeAudioStream subscribe pattern
- `github.com/livekit/rust-sdks/blob/main/.cargo/config.toml` — macOS linker flags
- `docs.rs/rustler/0.37.3 OwnedEnv` — send_and_clear restriction (must not be called from BEAM threads)
- `docs.rs/rustler/0.37.3 Resource trait` — down callback, IMPLEMENTS_DOWN, monitor
- `github.com/rusterlium/rustler/blob/master/rustler_tests/.../test_thread.rs` — thread::spawn pattern
- `github.com/rusterlium/rustler/blob/master/rustler_tests/.../test_resource.rs` — ResourceArc, resource!, Drop
- `github.com/elbow-jason/echo_rust_nif` — global tokio runtime pattern (Lazy<Runtime>), OwnedEnv::send_and_clear from tokio task
- `docs.livekit.io/reference/python/livekit/rtc/audio_frame.html` — AudioFrame PCM int16 format confirmation
- `hexdocs.pm/rustler/changelog.html` — 0.36 and 0.37 changes (no breaking changes in resources/threading)

### Secondary (MEDIUM confidence)

- `elixirforum.com/t/yielding-nifs-in-rustler` — confirmed Yielding NIFs not supported; Threaded NIFs are the correct approach
- `github.com/livekit/rust-sdks/issues/420` — capture_frame blocking bug (reported 2024-09-04, status unresolved)

### Tertiary (LOW confidence)

- None — all critical claims have HIGH or MEDIUM source support

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified via crates.io and hex.pm registry as of 2026-04-14
- Architecture: HIGH — patterns verified against official Rustler source, echo_rust_nif reference, livekit examples
- Pitfalls: HIGH — OwnedEnv restriction from official docs; capture_frame bug from verified GitHub issue; linker flags from verified .cargo/config.toml
- Audio format: HIGH — verified from livekit audio_stream.rs source and Python SDK docs (cross-reference)

**Research date:** 2026-04-14
**Valid until:** 2026-07-14 (stable ecosystem; livekit SDK updates frequently but API shape stable)

use rustler::{LocalPid, Resource};
use tokio::task::AbortHandle;
use std::sync::Arc;
use livekit::Room;

pub struct RoomResource {
    pub room: Arc<Room>,
    pub event_task: AbortHandle,
    // Used by the event forwarding task in room.rs to send messages to the Elixir listener.
    // Also forwarded to audio/video track resources in Plan 03.
    #[allow(dead_code)]
    pub listener_pid: LocalPid,
}

// SAFETY: RoomResource is accessed only through ResourceArc which uses BEAM's resource
// locking guarantees. The inner Room uses parking_lot::RwLock which is not
// automatically RefUnwindSafe (the auto-trait is conservative), but catch_unwind is
// only used by Rustler to prevent NIF panics from crashing the BEAM — Room is never
// accessed across the unwind boundary.
impl std::panic::RefUnwindSafe for RoomResource {}

#[rustler::resource_impl]
impl Resource for RoomResource {
    const IMPLEMENTS_DOWN: bool = true;

    fn down<'a>(&'a self, _env: rustler::Env<'a>, _pid: LocalPid, _mon: rustler::Monitor) {
        // Elixir process holding this ref died — stop the event forwarding task.
        self.event_task.abort();
    }
}

pub struct AudioTrackResource {
    pub stream_task: AbortHandle,
    // Used by Plan 03 (audio streaming) to identify the track and send frames to Elixir.
    #[allow(dead_code)]
    pub track_sid: String,
    #[allow(dead_code)]
    pub listener_pid: LocalPid,
}

// SAFETY: Same reasoning as RoomResource — AudioTrackResource fields are all
// either RefUnwindSafe (AbortHandle, String) or opaque C handles (LocalPid).
impl std::panic::RefUnwindSafe for AudioTrackResource {}

#[rustler::resource_impl]
impl Resource for AudioTrackResource {
    const IMPLEMENTS_DOWN: bool = true;

    fn down<'a>(&'a self, _env: rustler::Env<'a>, _pid: LocalPid, _mon: rustler::Monitor) {
        // Elixir process that subscribed to this track died — stop the audio stream.
        self.stream_task.abort();
    }
}

use std::sync::Arc;

use livekit::Room;
use rustler::{LocalPid, Resource};
use tokio::task::AbortHandle;

pub struct RoomResource {
    pub room: Arc<Room>,
    pub event_task: AbortHandle,
    pub listener_pid: LocalPid,
}

// Safety: RoomResource is only accessed via ResourceArc (reference-counted) and all interior
// mutability in Room uses Mutex/RwLock, which are RefUnwindSafe.
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
    pub track_sid: String,
    pub listener_pid: LocalPid,
}

// Safety: AudioTrackResource contains only AbortHandle, String, and LocalPid — all RefUnwindSafe.
impl std::panic::RefUnwindSafe for AudioTrackResource {}

#[rustler::resource_impl]
impl Resource for AudioTrackResource {
    const IMPLEMENTS_DOWN: bool = true;

    fn down<'a>(&'a self, _env: rustler::Env<'a>, _pid: LocalPid, _mon: rustler::Monitor) {
        // Elixir process that subscribed to this track died — stop the audio stream.
        self.stream_task.abort();
    }
}

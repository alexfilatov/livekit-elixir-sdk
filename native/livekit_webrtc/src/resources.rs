use rustler::{LocalPid, Resource};
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
        // Elixir process holding this ref died — stop the event forwarding task
        self.event_task.abort();
    }
}

pub struct AudioTrackResource {
    pub stream_task: AbortHandle,
    pub track_sid: String,
}

#[rustler::resource_impl]
impl Resource for AudioTrackResource {}

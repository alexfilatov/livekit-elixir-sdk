use std::sync::Arc;

use livekit::{
    publication::LocalTrackPublication, webrtc::audio_source::native::NativeAudioSource, Room,
};
use rustler::{LocalPid, Resource};
use tokio::{sync::OnceCell, task::AbortHandle};

pub struct RoomResource {
    pub room: Arc<Room>,
    pub event_task: AbortHandle,
    /// The agent's outgoing audio track. Published exactly once, on the first
    /// frame; every later frame is captured into the source held here. A track
    /// per frame is not a stream anybody can listen to.
    pub published_audio: OnceCell<(NativeAudioSource, LocalTrackPublication)>,
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
}

// Safety: AudioTrackResource contains only an AbortHandle, which is RefUnwindSafe.
impl std::panic::RefUnwindSafe for AudioTrackResource {}

#[rustler::resource_impl]
impl Resource for AudioTrackResource {
    const IMPLEMENTS_DOWN: bool = true;

    fn down<'a>(&'a self, _env: rustler::Env<'a>, _pid: LocalPid, _mon: rustler::Monitor) {
        // Elixir process that subscribed to this track died — stop the audio stream.
        self.stream_task.abort();
    }
}

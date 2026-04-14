mod atoms;
mod resources;
pub mod runtime;

use rustler::{Env, Term};

// Stub NIF declarations — implementations added in Plans 02 and 03
pub mod room {
    use rustler::{LocalPid, ResourceArc};
    use crate::resources::RoomResource;

    #[rustler::nif(schedule = "DirtyIo")]
    pub fn room_connect(
        _url: String,
        _token: String,
        _listener_pid: LocalPid,
    ) -> Result<ResourceArc<RoomResource>, rustler::Error> {
        Err(rustler::Error::RaiseAtom("not_implemented"))
    }

    #[rustler::nif(schedule = "DirtyIo")]
    pub fn room_disconnect(_room: ResourceArc<RoomResource>) -> rustler::Atom {
        crate::atoms::not_loaded()
    }
}

pub mod audio {
    use rustler::{LocalPid, ResourceArc};
    use crate::resources::{RoomResource, AudioTrackResource};

    #[rustler::nif(schedule = "DirtyIo")]
    pub fn audio_subscribe(
        _room: ResourceArc<RoomResource>,
        _track_sid: String,
        _subscriber_pid: LocalPid,
    ) -> Result<ResourceArc<AudioTrackResource>, rustler::Error> {
        Err(rustler::Error::RaiseAtom("not_implemented"))
    }

    #[rustler::nif(schedule = "DirtyIo")]
    pub fn audio_publish_frame(
        _room: ResourceArc<RoomResource>,
        _audio_binary: rustler::Binary,
        _sample_rate: u32,
        _channels: u32,
    ) -> rustler::Atom {
        crate::atoms::not_loaded()
    }
}

fn load(env: Env, _: Term) -> bool {
    // ALL resource types must be registered here or BEAM crashes on first use (Pitfall 7)
    env.register::<resources::RoomResource>().is_ok()
        && env.register::<resources::AudioTrackResource>().is_ok()
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

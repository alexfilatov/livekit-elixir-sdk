mod atoms;
mod audio;
mod resources;
pub mod runtime;

use rustler::{Env, Term};

// Stub NIF declarations for room — implementations added in Plan 02
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

fn load(env: Env, _: Term) -> bool {
    // ALL resource types must be registered here or BEAM crashes on first use (Pitfall 7)
    env.register::<resources::RoomResource>().is_ok()
        && env.register::<resources::AudioTrackResource>().is_ok()
}

// NIF functions are collected automatically via inventory — no explicit list needed
rustler::init!("Elixir.Livekit.WebRTC.Native", load = load);

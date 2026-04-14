mod atoms;
mod audio;
mod resources;
mod room;
pub mod runtime;

use rustler::{Env, Term};

fn load(env: Env, _: Term) -> bool {
    // ALL resource types must be registered here or BEAM crashes on first use
    env.register::<resources::RoomResource>().is_ok()
        && env.register::<resources::AudioTrackResource>().is_ok()
}

// NIF functions are collected automatically via inventory — no explicit list needed
rustler::init!("Elixir.Livekit.WebRTC.Native", load = load);

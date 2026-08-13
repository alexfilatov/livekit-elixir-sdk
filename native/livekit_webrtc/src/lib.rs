mod atoms;
mod audio;
mod resources;
mod room;
pub mod runtime;

use rustler::{Env, Term};

fn load(env: Env, _: Term) -> bool {
    // rustls 0.23 has no crypto provider unless one is installed for the
    // process. Nothing installs it here: livekit pulls rustls in with `ring`
    // available but not selected as the default, so every HTTPS request the
    // client makes fails instantly, before any I/O.
    //
    // The symptom is maddeningly indirect — connecting to a room reports
    // "failed to retrieve region info: error sending request for url (...)",
    // naming an address that resolves, is reachable, and serves a valid
    // certificate. It reads as a network fault and is not one.
    //
    // Ignoring the result on purpose: it only errors if a provider is already
    // installed, which is a success for our purposes.
    let _ = rustls::crypto::ring::default_provider().install_default();

    // ALL resource types must be registered here or BEAM crashes on first use
    env.register::<resources::RoomResource>().is_ok()
        && env.register::<resources::AudioTrackResource>().is_ok()
}

// NIF functions are collected automatically via inventory — no explicit list needed
rustler::init!("Elixir.Livekit.WebRTC.Native", load = load);

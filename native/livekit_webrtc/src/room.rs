use std::sync::Arc;

use livekit::{Room, RoomEvent, RoomOptions};
use rustler::{Encoder, LocalPid, OwnedEnv, ResourceArc};

use crate::atoms;
use crate::resources::RoomResource;

/// Connect to a LiveKit room and start the event forwarding loop.
///
/// Runs on a DirtyIo scheduler thread because `TOKIO.block_on` can take hundreds of
/// milliseconds (network round-trip). Using a dirty scheduler thread is mandatory for
/// NIFs that may block longer than 1 ms (ERTS requirement).
///
/// The returned `ResourceArc<RoomResource>` keeps the room alive and carries the
/// `AbortHandle` for the event task. When the resource is garbage-collected by BEAM,
/// `Resource::down` is invoked and the event task is aborted automatically.
#[rustler::nif(schedule = "DirtyIo")]
pub fn room_connect(
    url: String,
    token: String,
    listener_pid: LocalPid,
) -> Result<ResourceArc<RoomResource>, rustler::Error> {
    // Block on the DirtyIo thread — safe because dirty threads are not BEAM schedulers.
    // TOKIO.block_on runs the async future to completion synchronously on this thread.
    let result = crate::runtime::TOKIO.block_on(async {
        // RoomOptions is #[non_exhaustive] — cannot use struct literal with `..` spread
        // from outside the crate. Build via Default and then mutate the desired field.
        let mut opts = RoomOptions::default();
        opts.auto_subscribe = true;
        Room::connect(&url, &token, opts).await
    });

    let (room, rx) = result.map_err(|e| rustler::Error::RaiseTerm(Box::new(e.to_string())))?;

    let room = Arc::new(room);
    let pid = listener_pid;

    // Spawn event forwarding task on the global tokio runtime.
    //
    // CRITICAL: `rx` must be MOVED into the task — never assigned to `_` or dropped.
    // Dropping the receiver closes the channel and silently discards all future events
    // (Pitfall 6 from RESEARCH.md).
    //
    // `OwnedEnv::send_and_clear` is called inside this tokio worker thread — never from
    // a BEAM scheduler thread — satisfying Rustler's threading requirement (Pitfall 1).
    let event_task = crate::runtime::spawn(async move {
        let mut rx = rx;
        while let Some(event) = rx.recv().await {
            forward_room_event(&pid, event);
        }
    });

    Ok(ResourceArc::new(RoomResource {
        room,
        event_task: event_task.abort_handle(),
        listener_pid,
    }))
}

/// Disconnect from a LiveKit room and stop the event forwarding task.
///
/// Aborts the event task first (stopping new messages from being sent to the listener),
/// then performs a graceful WebRTC disconnect. Errors from `disconnect()` are ignored —
/// the room handle is being released regardless.
#[rustler::nif(schedule = "DirtyIo")]
pub fn room_disconnect(room: ResourceArc<RoomResource>) -> rustler::Atom {
    // Stop the event forwarding task before disconnect to prevent spurious messages.
    room.event_task.abort();
    // Graceful disconnect — fire-and-forget on error.
    crate::runtime::TOKIO.block_on(async {
        // The livekit crate uses `close()` for graceful disconnect (not `disconnect()`).
        room.room.close().await.ok();
    });
    atoms::ok()
}

/// Forward a single `RoomEvent` to the Elixir listener PID as an Erlang message.
///
/// Each invocation creates a fresh `OwnedEnv` (a cheap heap allocation), encodes the
/// event as an Erlang term, calls `send_and_clear` to atomically deliver the message and
/// release the env's memory.
///
/// **Thread safety:** This function MUST only be called from tokio worker threads (i.e.,
/// from inside a `crate::runtime::spawn` future). Calling `send_and_clear` from a
/// BEAM-managed thread causes a panic.
///
/// Unhandled `RoomEvent` variants (not in D-12) are silently discarded via the `_ => {}`
/// arm to keep the match exhaustive without breaking on new upstream variants.
fn forward_room_event(pid: &LocalPid, event: RoomEvent) {
    let mut env = OwnedEnv::new();
    match event {
        RoomEvent::ParticipantConnected(p) => {
            let identity = p.identity().to_string();
            let _ = env.send_and_clear(pid, move |env| {
                (atoms::participant_connected(), identity).encode(env)
            });
        }
        RoomEvent::ParticipantDisconnected(p) => {
            let identity = p.identity().to_string();
            let _ = env.send_and_clear(pid, move |env| {
                (atoms::participant_disconnected(), identity).encode(env)
            });
        }
        RoomEvent::TrackSubscribed { track, publication, participant } => {
            let track_sid = publication.sid().to_string();
            let identity = participant.identity().to_string();
            // Format the track kind as a lowercase string ("audio" / "video")
            let track_kind = format!("{:?}", track.kind()).to_lowercase();
            let _ = env.send_and_clear(pid, move |env| {
                (atoms::track_subscribed(), track_sid, identity, track_kind).encode(env)
            });
        }
        RoomEvent::TrackUnsubscribed { track: _track, publication, participant } => {
            let track_sid = publication.sid().to_string();
            let identity = participant.identity().to_string();
            let _ = env.send_and_clear(pid, move |env| {
                (atoms::track_unsubscribed(), track_sid, identity).encode(env)
            });
        }
        RoomEvent::TrackPublished { publication, participant } => {
            let track_sid = publication.sid().to_string();
            let identity = participant.identity().to_string();
            let _ = env.send_and_clear(pid, move |env| {
                (atoms::track_published(), track_sid, identity).encode(env)
            });
        }
        RoomEvent::TrackUnpublished { publication, participant } => {
            let track_sid = publication.sid().to_string();
            let identity = participant.identity().to_string();
            let _ = env.send_and_clear(pid, move |env| {
                (atoms::track_unpublished(), track_sid, identity).encode(env)
            });
        }
        RoomEvent::DataReceived { payload, topic, kind: _kind, participant } => {
            // payload is Arc<Vec<u8>>; clone the inner vec for sending to Elixir.
            let bytes: Vec<u8> = (*payload).clone();
            let topic_str = topic.unwrap_or_default();
            let identity =
                participant.map(|p| p.identity().to_string()).unwrap_or_default();
            let _ = env.send_and_clear(pid, move |env| {
                (atoms::data_received(), bytes, topic_str, identity).encode(env)
            });
        }
        RoomEvent::ConnectionQualityChanged { quality, participant } => {
            // participant here is `Participant` (not RemoteParticipant) — both have identity()
            let identity = participant.identity().to_string();
            let quality_str = format!("{:?}", quality).to_lowercase();
            let _ = env.send_and_clear(pid, move |env| {
                (atoms::connection_quality_changed(), identity, quality_str).encode(env)
            });
        }
        RoomEvent::Disconnected { reason } => {
            let reason_str = format!("{:?}", reason);
            let _ = env.send_and_clear(pid, move |env| {
                (atoms::disconnected(), reason_str).encode(env)
            });
        }
        // Silently ignore events not listed in D-12:
        // ParticipantActive, LocalTrackPublished, LocalTrackUnpublished, LocalTrackSubscribed,
        // TrackSubscriptionFailed, TrackMuted, TrackUnmuted, RoomMetadataChanged,
        // ParticipantMetadataChanged, ParticipantNameChanged, ActiveSpeakersChanged,
        // ConnectionStateChanged, Connected, Reconnecting, Reconnected, etc.
        _ => {}
    }
}

use std::time::Duration;

use futures::StreamExt;
use livekit::{
    options::TrackPublishOptions,
    track::{LocalAudioTrack, LocalTrack, RemoteAudioTrack, TrackSource},
    webrtc::{
        audio_frame::AudioFrame,
        audio_source::{native::NativeAudioSource, AudioSourceOptions, RtcAudioSource},
        audio_stream::native::{NativeAudioStream, NativeAudioStreamOptions},
    },
};
use rustler::{Encoder, LocalPid, OwnedBinary, OwnedEnv, ResourceArc};

use crate::atoms;
use crate::resources::{AudioTrackResource, RoomResource};

const TARGET_SAMPLE_RATE: i32 = 48_000;
const TARGET_CHANNELS: i32 = 1;
// 10ms worth of frames at 48kHz mono; bounded queue prevents memory buildup on slow consumers
const QUEUE_SIZE_FRAMES: usize = 480;
// Timeout guard against the known capture_frame blocking bug (RESEARCH.md Pitfall 2)
const CAPTURE_FRAME_TIMEOUT_MS: u64 = 500;

#[rustler::nif(schedule = "DirtyIo")]
pub fn audio_subscribe(
    room: ResourceArc<RoomResource>,
    track_sid: String,
    subscriber_pid: LocalPid,
) -> Result<ResourceArc<AudioTrackResource>, rustler::Error> {
    let sid = track_sid.clone();

    // Find the remote audio track in the room's participant list
    let audio_track = find_remote_audio_track(&room, &track_sid).ok_or_else(|| {
        rustler::Error::RaiseTerm(Box::new(format!("track not found: {}", track_sid)))
    })?;

    let stream_task = crate::runtime::spawn(async move {
        let rtc_track = audio_track.rtc_track();
        let mut stream = NativeAudioStream::with_options(
            rtc_track,
            TARGET_SAMPLE_RATE,
            TARGET_CHANNELS,
            NativeAudioStreamOptions { queue_size_frames: Some(QUEUE_SIZE_FRAMES) },
        );

        while let Some(frame) = stream.next().await {
            // Convert Vec<i16> to little-endian bytes — MUST use to_le_bytes()
            // to match Livekit.Agents.AudioFrame :pcm_16 format
            let bytes: Vec<u8> = frame.data.iter().flat_map(|s| s.to_le_bytes()).collect();

            let track_sid_clone = sid.clone();
            let mut env = OwnedEnv::new();
            // Safe: called from tokio worker thread, not a BEAM scheduler thread
            let _ = env.send_and_clear(&subscriber_pid, move |env| {
                // An OwnedBinary, not the Vec directly: rustler encodes Vec<u8>
                // as an Erlang list of integers, and every consumer of
                // {:audio_frame, _, _} expects a binary.
                let mut bin = OwnedBinary::new(bytes.len()).expect("audio frame allocation");
                bin.as_mut_slice().copy_from_slice(&bytes);

                (atoms::audio_frame(), track_sid_clone, bin.release(env)).encode(env)
            });
        }
    });

    Ok(ResourceArc::new(AudioTrackResource {
        stream_task: stream_task.abort_handle(),
    }))
}

/// Find a RemoteAudioTrack by its SID across all remote participants in the room.
fn find_remote_audio_track(room: &RoomResource, track_sid: &str) -> Option<RemoteAudioTrack> {
    for participant in room.room.remote_participants().values() {
        for track_pub in participant.track_publications().values() {
            if track_pub.sid().as_str() == track_sid {
                if let Some(track) = track_pub.track() {
                    if let livekit::track::RemoteTrack::Audio(audio_track) = track {
                        return Some(audio_track);
                    }
                }
            }
        }
    }
    None
}

/// Publish one frame of the agent's speech.
///
/// The first frame publishes the track; every frame after it is captured into
/// the source held on the room. Returns `:ok` or `{:error, reason}`.
///
/// Because capture paces in real time, this call lasts as long as the audio
/// does — a caller publishing a whole sentence blocks for the whole sentence.
/// ponytail: acceptable while the agent is speaking anyway; if barge-in needs
/// to interrupt mid-sentence, hand the chunk loop to a tokio task and let
/// Elixir cancel it.
#[rustler::nif(schedule = "DirtyIo")]
pub fn audio_publish_frame<'a>(
    env: rustler::Env<'a>,
    room: ResourceArc<RoomResource>,
    audio_binary: rustler::Binary,
    sample_rate: u32,
    channels: u32,
) -> rustler::Term<'a> {
    // Convert incoming little-endian int16 bytes back to Vec<i16>.
    // This is the inverse of the subscribe path's to_le_bytes() conversion.
    let bytes = audio_binary.as_slice();
    let samples: Vec<i16> = bytes
        .chunks_exact(2)
        .map(|chunk| i16::from_le_bytes([chunk[0], chunk[1]]))
        .collect();

    let result: Result<(), String> = crate::runtime::TOKIO.block_on(async {
        // Publish exactly once. The sample rate and channel count of the first
        // frame define the track; the pipeline emits a single format throughout.
        let (source, _publication) = room
            .published_audio
            .get_or_try_init(|| async {
                // queue_size_ms=100 (a multiple of 10) enables buffered capture.
                let source = NativeAudioSource::new(
                    AudioSourceOptions {
                        echo_cancellation: false,
                        noise_suppression: false,
                        auto_gain_control: false,
                    },
                    sample_rate,
                    channels,
                    100, // queue_size_ms — must be a multiple of 10
                );

                let track = LocalAudioTrack::create_audio_track(
                    "agent_audio",
                    RtcAudioSource::Native(source.clone()),
                );

                room.room
                    .local_participant()
                    .publish_track(
                        LocalTrack::Audio(track),
                        TrackPublishOptions {
                            source: TrackSource::Microphone,
                            ..Default::default()
                        },
                    )
                    .await
                    .map(|publication| (source, publication))
                    .map_err(|e| format!("publish_track failed: {}", e))
            })
            .await?;

        // capture_frame takes 10ms of audio and paces itself against the
        // source's queue, so a whole synthesised sentence handed over in one
        // call blocks until it has played and trips the timeout. A greeting is
        // seconds long; the caller has no idea it is meant to arrive in
        // 10ms slices, so the slicing happens here.
        let frame_samples = (sample_rate as usize / 100) * channels as usize;

        for chunk in samples.chunks(frame_samples) {
            let frame = AudioFrame {
                data: chunk.into(),
                sample_rate,
                num_channels: channels,
                samples_per_channel: (chunk.len() / channels as usize) as u32,
            };

            // Per chunk, not per call: pacing means each one waits roughly its
            // own duration, and the guard is against a wedged capture rather
            // than against the audio being long.
            match tokio::time::timeout(
                Duration::from_millis(CAPTURE_FRAME_TIMEOUT_MS),
                source.capture_frame(&frame),
            )
            .await
            {
                Ok(Ok(())) => {}
                Ok(Err(e)) => return Err(format!("capture_frame failed: {}", e)),
                Err(_elapsed) => return Err("capture_frame timed out".to_string()),
            }
        }

        Ok(())
    });

    match result {
        Ok(()) => atoms::ok().encode(env),
        Err(reason) => (atoms::error(), reason).encode(env),
    }
}

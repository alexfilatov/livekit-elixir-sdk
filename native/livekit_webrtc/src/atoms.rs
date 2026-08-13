rustler::atoms! {
    ok,
    error,
    // Room events (D-12)
    participant_connected,
    participant_disconnected,
    track_subscribed,
    track_unsubscribed,
    track_published,
    track_unpublished,
    data_received,
    connection_quality_changed,
    disconnected,
    // Track kinds, as carried by track_subscribed
    audio,
    video,
    // Audio (D-13)
    audio_frame,
    // General
    not_loaded,
}

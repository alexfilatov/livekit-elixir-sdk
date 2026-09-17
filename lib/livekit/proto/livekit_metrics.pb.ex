defmodule Livekit.MetricLabel do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:AGENTS_LLM_TTFT, 0)
  field(:AGENTS_STT_TTFT, 1)
  field(:AGENTS_TTS_TTFB, 2)
  field(:CLIENT_VIDEO_SUBSCRIBER_FREEZE_COUNT, 3)
  field(:CLIENT_VIDEO_SUBSCRIBER_TOTAL_FREEZE_DURATION, 4)
  field(:CLIENT_VIDEO_SUBSCRIBER_PAUSE_COUNT, 5)
  field(:CLIENT_VIDEO_SUBSCRIBER_TOTAL_PAUSES_DURATION, 6)
  field(:CLIENT_AUDIO_SUBSCRIBER_CONCEALED_SAMPLES, 7)
  field(:CLIENT_AUDIO_SUBSCRIBER_SILENT_CONCEALED_SAMPLES, 8)
  field(:CLIENT_AUDIO_SUBSCRIBER_CONCEALMENT_EVENTS, 9)
  field(:CLIENT_AUDIO_SUBSCRIBER_INTERRUPTION_COUNT, 10)
  field(:CLIENT_AUDIO_SUBSCRIBER_TOTAL_INTERRUPTION_DURATION, 11)
  field(:CLIENT_SUBSCRIBER_JITTER_BUFFER_DELAY, 12)
  field(:CLIENT_SUBSCRIBER_JITTER_BUFFER_EMITTED_COUNT, 13)
  field(:CLIENT_VIDEO_PUBLISHER_QUALITY_LIMITATION_DURATION_BANDWIDTH, 14)
  field(:CLIENT_VIDEO_PUBLISHER_QUALITY_LIMITATION_DURATION_CPU, 15)
  field(:CLIENT_VIDEO_PUBLISHER_QUALITY_LIMITATION_DURATION_OTHER, 16)
  field(:PUBLISHER_RTT, 17)
  field(:SERVER_MESH_RTT, 18)
  field(:SUBSCRIBER_RTT, 19)
  field(:METRIC_LABEL_PREDEFINED_MAX_VALUE, 4096)
end

defmodule Livekit.MetricsBatch do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:timestamp_ms, 1, type: :int64, json_name: "timestampMs")

  field(:normalized_timestamp, 2,
    type: Google.Protobuf.Timestamp,
    json_name: "normalizedTimestamp"
  )

  field(:str_data, 3, repeated: true, type: :string, json_name: "strData")
  field(:time_series, 4, repeated: true, type: Livekit.TimeSeriesMetric, json_name: "timeSeries")
  field(:events, 5, repeated: true, type: Livekit.EventMetric)
end

defmodule Livekit.TimeSeriesMetric do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:label, 1, type: :uint32)
  field(:participant_identity, 2, type: :uint32, json_name: "participantIdentity")
  field(:track_sid, 3, type: :uint32, json_name: "trackSid")
  field(:samples, 4, repeated: true, type: Livekit.MetricSample)
  field(:rid, 5, type: :uint32)
end

defmodule Livekit.MetricSample do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:timestamp_ms, 1, type: :int64, json_name: "timestampMs")

  field(:normalized_timestamp, 2,
    type: Google.Protobuf.Timestamp,
    json_name: "normalizedTimestamp"
  )

  field(:value, 3, type: :float)
end

defmodule Livekit.EventMetric do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:label, 1, type: :uint32)
  field(:participant_identity, 2, type: :uint32, json_name: "participantIdentity")
  field(:track_sid, 3, type: :uint32, json_name: "trackSid")
  field(:start_timestamp_ms, 4, type: :int64, json_name: "startTimestampMs")
  field(:end_timestamp_ms, 5, proto3_optional: true, type: :int64, json_name: "endTimestampMs")

  field(:normalized_start_timestamp, 6,
    type: Google.Protobuf.Timestamp,
    json_name: "normalizedStartTimestamp"
  )

  field(:normalized_end_timestamp, 7,
    proto3_optional: true,
    type: Google.Protobuf.Timestamp,
    json_name: "normalizedEndTimestamp"
  )

  field(:metadata, 8, type: :string)
  field(:rid, 9, type: :uint32)
end

defmodule Livekit.MetricsRecordingHeader.RoomTagsEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Livekit.MetricsRecordingHeader do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:room_id, 1, type: :string, json_name: "roomId", deprecated: false)
  field(:duration, 3, type: :uint64)
  field(:start_time, 4, type: Google.Protobuf.Timestamp, json_name: "startTime")

  field(:room_tags, 5,
    repeated: true,
    type: Livekit.MetricsRecordingHeader.RoomTagsEntry,
    json_name: "roomTags",
    map: true
  )

  field(:room_name, 6, type: :string, json_name: "roomName")
  field(:room_start_time, 7, type: Google.Protobuf.Timestamp, json_name: "roomStartTime")
  field(:job_id, 8, type: :string, json_name: "jobId")
  field(:simulated, 9, type: :bool)
  field(:redaction_enabled, 10, type: :bool, json_name: "redactionEnabled")
end

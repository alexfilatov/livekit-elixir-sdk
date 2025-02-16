defmodule Livekit.DisconnectReason do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :UNKNOWN_REASON, 0
  field :CLIENT_INITIATED, 1
  field :DUPLICATE_IDENTITY, 2
  field :SERVER_SHUTDOWN, 3
  field :PARTICIPANT_REMOVED, 4
  field :ROOM_DELETED, 5
  field :STATE_MISMATCH, 6
  field :JOIN_FAILURE, 7
end

defmodule Livekit.TrackSource do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :UNKNOWN, 0
  field :CAMERA, 1
  field :MICROPHONE, 2
  field :SCREEN_SHARE, 3
  field :SCREEN_SHARE_AUDIO, 4
end

defmodule Livekit.TrackType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :AUDIO, 0
  field :VIDEO, 1
  field :DATA, 2
end

defmodule Livekit.VideoQuality do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :LOW, 0
  field :MEDIUM, 1
  field :HIGH, 2
end

defmodule Livekit.AudioTrackFeature do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :UNSPECIFIED, 0
  field :VOICE_ACTIVITY_DETECTION, 1
  field :MUSIC_MODE, 2
end

defmodule Livekit.ParticipantInfo.State do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :JOINING, 0
  field :JOINED, 1
  field :ACTIVE, 2
  field :DISCONNECTED, 3
end

defmodule Livekit.ParticipantInfo.Kind do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :STANDARD, 0
  field :INGRESS, 1
  field :EGRESS, 2
  field :SIP, 3
  field :AGENT, 4
end

defmodule Livekit.Encryption.Type do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :NONE, 0
  field :GCM, 1
  field :CUSTOM, 2
end

defmodule Livekit.DataPacket.Kind do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :RELIABLE, 0
  field :LOSSY, 1
end

defmodule Livekit.Room do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :sid, 1, type: :string
  field :name, 2, type: :string
  field :empty_timeout, 3, type: :uint32, json_name: "emptyTimeout"
  field :departure_timeout, 14, type: :uint32, json_name: "departureTimeout"
  field :max_participants, 4, type: :uint32, json_name: "maxParticipants"
  field :creation_time, 5, type: :int64, json_name: "creationTime"
  field :creation_time_ms, 15, type: :int64, json_name: "creationTimeMs"
  field :turn_password, 6, type: :string, json_name: "turnPassword"
  field :enabled_codecs, 7, repeated: true, type: Livekit.Codec, json_name: "enabledCodecs"
  field :metadata, 8, type: :string
  field :num_participants, 9, type: :uint32, json_name: "numParticipants"
  field :num_publishers, 11, type: :uint32, json_name: "numPublishers"
  field :active_recording, 10, type: :bool, json_name: "activeRecording"
  field :version, 13, type: Livekit.TimedVersion
end

defmodule Livekit.Codec do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :mime, 1, type: :string
  field :fmtp_line, 2, type: :string, json_name: "fmtpLine"
end

defmodule Livekit.TimedVersion do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :unix_micro, 1, type: :int64, json_name: "unixMicro"
  field :ticks, 2, type: :int32
end

defmodule Livekit.PlayoutDelay do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :enabled, 1, type: :bool
  field :min, 2, type: :uint32
  field :max, 3, type: :uint32
end

defmodule Livekit.ParticipantPermission do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :can_subscribe, 1, type: :bool, json_name: "canSubscribe"
  field :can_publish, 2, type: :bool, json_name: "canPublish"
  field :can_publish_data, 3, type: :bool, json_name: "canPublishData"

  field :can_publish_sources, 9,
    repeated: true,
    type: Livekit.TrackSource,
    json_name: "canPublishSources",
    enum: true

  field :hidden, 7, type: :bool
  field :recorder, 8, type: :bool, deprecated: true
  field :can_update_metadata, 10, type: :bool, json_name: "canUpdateMetadata"
  field :agent, 11, type: :bool, deprecated: true
  field :can_subscribe_metrics, 12, type: :bool, json_name: "canSubscribeMetrics"
end

defmodule Livekit.ParticipantInfo.AttributesEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Livekit.ParticipantInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :sid, 1, type: :string
  field :identity, 2, type: :string
  field :state, 3, type: Livekit.ParticipantInfo.State, enum: true
  field :tracks, 4, repeated: true, type: Livekit.TrackInfo
  field :metadata, 5, type: :string
  field :joined_at, 6, type: :int64, json_name: "joinedAt"
  field :joined_at_ms, 17, type: :int64, json_name: "joinedAtMs"
  field :name, 9, type: :string
  field :version, 10, type: :uint32
  field :permission, 11, type: Livekit.ParticipantPermission
  field :region, 12, type: :string
  field :is_publisher, 13, type: :bool, json_name: "isPublisher"
  field :kind, 14, type: Livekit.ParticipantInfo.Kind, enum: true
  field :attributes, 15, repeated: true, type: Livekit.ParticipantInfo.AttributesEntry, map: true

  field :disconnect_reason, 16,
    type: Livekit.DisconnectReason,
    json_name: "disconnectReason",
    enum: true
end

defmodule Livekit.TrackInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :sid, 1, type: :string
  field :type, 2, type: Livekit.TrackType, enum: true
  field :name, 3, type: :string
  field :muted, 4, type: :bool
  field :width, 5, type: :uint32
  field :height, 6, type: :uint32
  field :simulcast, 7, type: :bool
  field :disable_dtx, 8, type: :bool, json_name: "disableDtx"
  field :source, 9, type: Livekit.TrackSource, enum: true
  field :layers, 10, repeated: true, type: Livekit.VideoLayer
  field :mime_type, 11, type: :string, json_name: "mimeType"
  field :mid, 12, type: :string
  field :codecs, 13, repeated: true, type: Livekit.SimulcastCodecInfo
  field :stereo, 14, type: :bool
  field :disable_red, 15, type: :bool, json_name: "disableRed"
  field :encryption, 16, type: Livekit.Encryption.Type, enum: true
  field :stream, 17, type: :string
  field :version, 18, type: Livekit.TimedVersion

  field :audio_features, 19,
    repeated: true,
    type: Livekit.AudioTrackFeature,
    json_name: "audioFeatures",
    enum: true
end

defmodule Livekit.VideoLayer do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :quality, 1, type: Livekit.VideoQuality, enum: true
  field :width, 2, type: :uint32
  field :height, 3, type: :uint32
  field :bitrate, 4, type: :uint32
  field :ssrc, 5, type: :uint32
end

defmodule Livekit.SimulcastCodecInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :mime_type, 1, type: :string, json_name: "mimeType"
  field :mid, 2, type: :string
  field :cid, 3, type: :string
  field :layers, 4, repeated: true, type: Livekit.VideoLayer
end

defmodule Livekit.Encryption do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3
end

defmodule Livekit.DataPacket do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3
end

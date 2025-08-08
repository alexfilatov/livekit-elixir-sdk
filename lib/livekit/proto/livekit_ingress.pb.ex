defmodule Livekit.IngressInput do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :RTMP_INPUT, 0
  field :WHIP_INPUT, 1
  field :URL_INPUT, 2
end

defmodule Livekit.IngressAudioEncodingPreset do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :OPUS_STEREO_96KBPS, 0
  field :OPUS_MONO_64KBS, 1
end

defmodule Livekit.IngressVideoEncodingPreset do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :H264_720P_30FPS_3_LAYERS, 0
  field :H264_1080P_30FPS_3_LAYERS, 1
  field :H264_540P_25FPS_2_LAYERS, 2
  field :H264_720P_30FPS_1_LAYER, 3
  field :H264_1080P_30FPS_1_LAYER, 4
  field :H264_720P_30FPS_3_LAYERS_HIGH_MOTION, 5
  field :H264_1080P_30FPS_3_LAYERS_HIGH_MOTION, 6
  field :H264_540P_25FPS_2_LAYERS_HIGH_MOTION, 7
  field :H264_720P_30FPS_1_LAYER_HIGH_MOTION, 8
  field :H264_1080P_30FPS_1_LAYER_HIGH_MOTION, 9
end

defmodule Livekit.IngressState.Status do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :ENDPOINT_INACTIVE, 0
  field :ENDPOINT_BUFFERING, 1
  field :ENDPOINT_PUBLISHING, 2
  field :ENDPOINT_ERROR, 3
  field :ENDPOINT_COMPLETE, 4
end

defmodule Livekit.CreateIngressRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :input_type, 1, type: Livekit.IngressInput, json_name: "inputType", enum: true
  field :url, 9, type: :string
  field :name, 2, type: :string
  field :room_name, 3, type: :string, json_name: "roomName"
  field :participant_identity, 4, type: :string, json_name: "participantIdentity"
  field :participant_name, 5, type: :string, json_name: "participantName"
  field :participant_metadata, 10, type: :string, json_name: "participantMetadata"
  field :bypass_transcoding, 8, type: :bool, json_name: "bypassTranscoding", deprecated: true

  field :enable_transcoding, 11,
    proto3_optional: true,
    type: :bool,
    json_name: "enableTranscoding"

  field :audio, 6, type: Livekit.IngressAudioOptions
  field :video, 7, type: Livekit.IngressVideoOptions
  field :enabled, 12, proto3_optional: true, type: :bool
end

defmodule Livekit.IngressAudioOptions do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof :encoding_options, 0

  field :name, 1, type: :string
  field :source, 2, type: Livekit.TrackSource, enum: true
  field :preset, 3, type: Livekit.IngressAudioEncodingPreset, enum: true, oneof: 0
  field :options, 4, type: Livekit.IngressAudioEncodingOptions, oneof: 0
end

defmodule Livekit.IngressVideoOptions do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof :encoding_options, 0

  field :name, 1, type: :string
  field :source, 2, type: Livekit.TrackSource, enum: true
  field :preset, 3, type: Livekit.IngressVideoEncodingPreset, enum: true, oneof: 0
  field :options, 4, type: Livekit.IngressVideoEncodingOptions, oneof: 0
end

defmodule Livekit.IngressAudioEncodingOptions do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :audio_codec, 1, type: Livekit.AudioCodec, json_name: "audioCodec", enum: true
  field :bitrate, 2, type: :uint32
  field :disable_dtx, 3, type: :bool, json_name: "disableDtx"
  field :channels, 4, type: :uint32
end

defmodule Livekit.IngressVideoEncodingOptions do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :video_codec, 1, type: Livekit.VideoCodec, json_name: "videoCodec", enum: true
  field :frame_rate, 2, type: :double, json_name: "frameRate"
  field :layers, 3, repeated: true, type: Livekit.VideoLayer
end

defmodule Livekit.IngressInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :ingress_id, 1, type: :string, json_name: "ingressId"
  field :name, 2, type: :string
  field :stream_key, 3, type: :string, json_name: "streamKey"
  field :url, 4, type: :string
  field :input_type, 5, type: Livekit.IngressInput, json_name: "inputType", enum: true
  field :bypass_transcoding, 13, type: :bool, json_name: "bypassTranscoding", deprecated: true

  field :enable_transcoding, 15,
    proto3_optional: true,
    type: :bool,
    json_name: "enableTranscoding"

  field :audio, 6, type: Livekit.IngressAudioOptions
  field :video, 7, type: Livekit.IngressVideoOptions
  field :room_name, 8, type: :string, json_name: "roomName"
  field :participant_identity, 9, type: :string, json_name: "participantIdentity"
  field :participant_name, 10, type: :string, json_name: "participantName"
  field :participant_metadata, 14, type: :string, json_name: "participantMetadata"
  field :reusable, 11, type: :bool
  field :state, 12, type: Livekit.IngressState
  field :enabled, 16, proto3_optional: true, type: :bool
end

defmodule Livekit.IngressState do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :status, 1, type: Livekit.IngressState.Status, enum: true
  field :error, 2, type: :string
  field :video, 3, type: Livekit.InputVideoState
  field :audio, 4, type: Livekit.InputAudioState
  field :room_id, 5, type: :string, json_name: "roomId"
  field :started_at, 7, type: :int64, json_name: "startedAt"
  field :ended_at, 8, type: :int64, json_name: "endedAt"
  field :updated_at, 10, type: :int64, json_name: "updatedAt"
  field :resource_id, 9, type: :string, json_name: "resourceId"
  field :tracks, 6, repeated: true, type: Livekit.TrackInfo
end

defmodule Livekit.InputVideoState do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :mime_type, 1, type: :string, json_name: "mimeType"
  field :average_bitrate, 2, type: :uint32, json_name: "averageBitrate"
  field :width, 3, type: :uint32
  field :height, 4, type: :uint32
  field :framerate, 5, type: :double
end

defmodule Livekit.InputAudioState do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :mime_type, 1, type: :string, json_name: "mimeType"
  field :average_bitrate, 2, type: :uint32, json_name: "averageBitrate"
  field :channels, 3, type: :uint32
  field :sample_rate, 4, type: :uint32, json_name: "sampleRate"
end

defmodule Livekit.UpdateIngressRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :ingress_id, 1, type: :string, json_name: "ingressId"
  field :name, 2, type: :string
  field :room_name, 3, type: :string, json_name: "roomName"
  field :participant_identity, 4, type: :string, json_name: "participantIdentity"
  field :participant_name, 5, type: :string, json_name: "participantName"
  field :participant_metadata, 9, type: :string, json_name: "participantMetadata"

  field :bypass_transcoding, 8,
    proto3_optional: true,
    type: :bool,
    json_name: "bypassTranscoding",
    deprecated: true

  field :enable_transcoding, 10,
    proto3_optional: true,
    type: :bool,
    json_name: "enableTranscoding"

  field :audio, 6, type: Livekit.IngressAudioOptions
  field :video, 7, type: Livekit.IngressVideoOptions
  field :enabled, 11, proto3_optional: true, type: :bool
end

defmodule Livekit.ListIngressRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :room_name, 1, type: :string, json_name: "roomName"
  field :ingress_id, 2, type: :string, json_name: "ingressId"
end

defmodule Livekit.ListIngressResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :items, 1, repeated: true, type: Livekit.IngressInfo
end

defmodule Livekit.DeleteIngressRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :ingress_id, 1, type: :string, json_name: "ingressId"
end

defmodule Livekit.Ingress.Service do
  @moduledoc false

  use GRPC.Service, name: "livekit.Ingress", protoc_gen_elixir_version: "0.15.0"

  rpc :CreateIngress, Livekit.CreateIngressRequest, Livekit.IngressInfo

  rpc :UpdateIngress, Livekit.UpdateIngressRequest, Livekit.IngressInfo

  rpc :ListIngress, Livekit.ListIngressRequest, Livekit.ListIngressResponse

  rpc :DeleteIngress, Livekit.DeleteIngressRequest, Livekit.IngressInfo
end

defmodule Livekit.Ingress.Stub do
  @moduledoc false

  use GRPC.Stub, service: Livekit.Ingress.Service
end

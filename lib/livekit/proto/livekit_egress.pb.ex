defmodule Livekit.EgressStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:EGRESS_STARTING, 0)
  field(:EGRESS_ACTIVE, 1)
  field(:EGRESS_ENDING, 2)
  field(:EGRESS_COMPLETE, 3)
  field(:EGRESS_FAILED, 4)
end

defmodule Livekit.StreamProtocol do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:DEFAULT_PROTOCOL, 0)
  field(:RTMP, 1)
  field(:SRT, 2)
end

defmodule Livekit.EncodedFileType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:DEFAULT_FILETYPE, 0)
  field(:MP4, 1)
  field(:OGG, 2)
end

defmodule Livekit.EncodingOptionsPreset do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:H264_720P_30, 0)
  field(:H264_720P_60, 1)
  field(:H264_1080P_30, 2)
  field(:H264_1080P_60, 3)
  field(:PORTRAIT_H264_720P_30, 4)
  field(:PORTRAIT_H264_720P_60, 5)
  field(:PORTRAIT_H264_1080P_30, 6)
  field(:PORTRAIT_H264_1080P_60, 7)
end

defmodule Livekit.AudioMixing do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:DEFAULT_MIXING, 0)
  field(:DUAL_CHANNEL_AGENT, 1)
  field(:DUAL_CHANNEL_ALTERNATE, 2)
end

defmodule Livekit.EgressInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:egress_id, 1, type: :string, json_name: "egressId")
  field(:room_id, 2, type: :string, json_name: "roomId")
  field(:room_name, 3, type: :string, json_name: "roomName")
  field(:status, 4, type: Livekit.EgressStatus, enum: true)
  field(:error, 5, type: :string)
end

defmodule Livekit.RoomCompositeEgressRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  oneof(:output, 0)

  oneof(:options, 1)

  field(:room_name, 1, type: :string, json_name: "roomName")
  field(:layout, 2, type: :string)
  field(:audio_only, 3, type: :bool, json_name: "audioOnly")
  field(:audio_mixing, 15, type: Livekit.AudioMixing, json_name: "audioMixing", enum: true)
  field(:video_only, 4, type: :bool, json_name: "videoOnly")
  field(:custom_base_url, 5, type: :string, json_name: "customBaseUrl")
  field(:file, 6, type: Livekit.EncodedFileOutput, oneof: 0, deprecated: true)
  field(:stream, 7, type: Livekit.StreamOutput, oneof: 0, deprecated: true)
  field(:segments, 10, type: Livekit.SegmentedFileOutput, oneof: 0, deprecated: true)
  field(:preset, 8, type: Livekit.EncodingOptionsPreset, enum: true, oneof: 1)
  field(:advanced, 9, type: Livekit.EncodingOptions, oneof: 1)

  field(:file_outputs, 11,
    repeated: true,
    type: Livekit.EncodedFileOutput,
    json_name: "fileOutputs"
  )

  field(:stream_outputs, 12,
    repeated: true,
    type: Livekit.StreamOutput,
    json_name: "streamOutputs"
  )

  field(:segment_outputs, 13,
    repeated: true,
    type: Livekit.SegmentedFileOutput,
    json_name: "segmentOutputs"
  )

  field(:image_outputs, 14, repeated: true, type: Livekit.ImageOutput, json_name: "imageOutputs")
end

defmodule Livekit.WebEgressRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  oneof(:options, 0)

  field(:url, 1, type: :string)
  field(:audio_only, 2, type: :bool, json_name: "audioOnly")
  field(:video_only, 3, type: :bool, json_name: "videoOnly")
  field(:preset, 4, type: Livekit.EncodingOptionsPreset, enum: true, oneof: 0)
  field(:advanced, 5, type: Livekit.EncodingOptions, oneof: 0)
end

defmodule Livekit.ParticipantEgressRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  oneof(:options, 0)

  field(:room_name, 1, type: :string, json_name: "roomName")
  field(:identity, 2, type: :string)
  field(:preset, 3, type: Livekit.EncodingOptionsPreset, enum: true, oneof: 0)
  field(:advanced, 4, type: Livekit.EncodingOptions, oneof: 0)
end

defmodule Livekit.TrackCompositeEgressRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  oneof(:options, 0)

  field(:room_name, 1, type: :string, json_name: "roomName")
  field(:audio_track_id, 2, type: :string, json_name: "audioTrackId")
  field(:video_track_id, 3, type: :string, json_name: "videoTrackId")
  field(:preset, 4, type: Livekit.EncodingOptionsPreset, enum: true, oneof: 0)
  field(:advanced, 5, type: Livekit.EncodingOptions, oneof: 0)
end

defmodule Livekit.TrackEgressRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:room_name, 1, type: :string, json_name: "roomName")
  field(:track_id, 2, type: :string, json_name: "trackId")
  field(:filepath, 3, type: :string)
end

defmodule Livekit.UpdateLayoutRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:egress_id, 1, type: :string, json_name: "egressId")
  field(:layout, 2, type: :string)
end

defmodule Livekit.UpdateStreamRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:egress_id, 1, type: :string, json_name: "egressId")
  field(:add_output_urls, 2, repeated: true, type: :string, json_name: "addOutputUrls")
  field(:remove_output_urls, 3, repeated: true, type: :string, json_name: "removeOutputUrls")
end

defmodule Livekit.ListEgressRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:room_name, 1, type: :string, json_name: "roomName")
  field(:egress_id, 2, type: :string, json_name: "egressId")
end

defmodule Livekit.ListEgressResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:items, 1, repeated: true, type: Livekit.EgressInfo)
end

defmodule Livekit.StopEgressRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:egress_id, 1, type: :string, json_name: "egressId")
end

defmodule Livekit.EncodedFileOutput do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  oneof(:output, 0)

  field(:file_type, 1, type: Livekit.EncodedFileType, json_name: "fileType", enum: true)
  field(:filepath, 2, type: :string)
  field(:disable_manifest, 6, type: :bool, json_name: "disableManifest")
  field(:s3, 3, type: Livekit.S3Upload, oneof: 0)
  field(:gcp, 4, type: Livekit.GCPUpload, oneof: 0)
  field(:azure, 5, type: Livekit.AzureBlobUpload, oneof: 0)
  field(:aliOSS, 7, type: Livekit.AliOSSUpload, oneof: 0)
end

defmodule Livekit.S3Upload do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:bucket, 1, type: :string)
  field(:aws_credentials, 2, type: :string, json_name: "awsCredentials")
end

defmodule Livekit.GCPUpload do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:bucket, 1, type: :string)
  field(:credentials, 2, type: :string)
end

defmodule Livekit.AzureBlobUpload do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:container_name, 1, type: :string, json_name: "containerName")
  field(:credentials, 2, type: :string)
end

defmodule Livekit.AliOSSUpload do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:bucket, 1, type: :string)
  field(:credentials, 2, type: :string)
end

defmodule Livekit.StreamOutput do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:protocol, 1, type: Livekit.StreamProtocol, enum: true)
  field(:urls, 2, repeated: true, type: :string)
end

defmodule Livekit.SegmentedFileOutput do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  oneof(:output, 0)

  field(:filepath, 1, type: :string)
  field(:s3, 2, type: Livekit.S3Upload, oneof: 0)
  field(:gcp, 3, type: Livekit.GCPUpload, oneof: 0)
  field(:azure, 4, type: Livekit.AzureBlobUpload, oneof: 0)
  field(:aliOSS, 5, type: Livekit.AliOSSUpload, oneof: 0)
end

defmodule Livekit.ImageOutput do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  oneof(:output, 0)

  field(:filepath, 1, type: :string)
  field(:s3, 2, type: Livekit.S3Upload, oneof: 0)
  field(:gcp, 3, type: Livekit.GCPUpload, oneof: 0)
  field(:azure, 4, type: Livekit.AzureBlobUpload, oneof: 0)
  field(:aliOSS, 5, type: Livekit.AliOSSUpload, oneof: 0)
end

defmodule Livekit.AutoParticipantEgress do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:preset, 1, type: :string)
end

defmodule Livekit.AutoTrackEgress do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:preset, 1, type: :string)
end

defmodule Livekit.Egress.Service do
  @moduledoc false

  use GRPC.Service, name: "livekit.Egress", protoc_gen_elixir_version: "0.14.0"

  rpc(:StartRoomCompositeEgress, Livekit.RoomCompositeEgressRequest, Livekit.EgressInfo)

  rpc(:StartWebEgress, Livekit.WebEgressRequest, Livekit.EgressInfo)

  rpc(:StartParticipantEgress, Livekit.ParticipantEgressRequest, Livekit.EgressInfo)

  rpc(:StartTrackCompositeEgress, Livekit.TrackCompositeEgressRequest, Livekit.EgressInfo)

  rpc(:StartTrackEgress, Livekit.TrackEgressRequest, Livekit.EgressInfo)

  rpc(:UpdateLayout, Livekit.UpdateLayoutRequest, Livekit.EgressInfo)

  rpc(:UpdateStream, Livekit.UpdateStreamRequest, Livekit.EgressInfo)

  rpc(:ListEgress, Livekit.ListEgressRequest, Livekit.ListEgressResponse)

  rpc(:StopEgress, Livekit.StopEgressRequest, Livekit.EgressInfo)
end

defmodule Livekit.Egress.Stub do
  @moduledoc false

  use GRPC.Stub, service: Livekit.Egress.Service
end

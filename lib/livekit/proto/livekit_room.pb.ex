defmodule Livekit.DataPacketKind do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :RELIABLE, 0
  field :LOSSY, 1
end

defmodule Livekit.CreateRoomRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :name, 1, type: :string
  field :room_preset, 12, type: :string, json_name: "roomPreset"
  field :empty_timeout, 2, type: :uint32, json_name: "emptyTimeout"
  field :departure_timeout, 10, type: :uint32, json_name: "departureTimeout"
  field :max_participants, 3, type: :uint32, json_name: "maxParticipants"
  field :node_id, 4, type: :string, json_name: "nodeId"
  field :metadata, 5, type: :string
  field :egress, 6, type: Livekit.RoomEgress
  field :min_playout_delay, 7, type: :uint32, json_name: "minPlayoutDelay"
  field :max_playout_delay, 8, type: :uint32, json_name: "maxPlayoutDelay"
  field :sync_streams, 9, type: :bool, json_name: "syncStreams"
  field :replay_enabled, 13, type: :bool, json_name: "replayEnabled"
  field :agents, 14, repeated: true, type: Livekit.RoomAgentDispatch
end

defmodule Livekit.RoomEgress do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :room, 1, type: Livekit.RoomCompositeEgressRequest
  field :participant, 3, type: Livekit.AutoParticipantEgress
  field :tracks, 2, type: Livekit.AutoTrackEgress
end

defmodule Livekit.RoomAgent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :dispatches, 1, repeated: true, type: Livekit.RoomAgentDispatch
end

defmodule Livekit.ListRoomsRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :names, 1, repeated: true, type: :string
end

defmodule Livekit.ListRoomsResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :rooms, 1, repeated: true, type: Livekit.Room
end

defmodule Livekit.DeleteRoomRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :room, 1, type: :string
end

defmodule Livekit.DeleteRoomResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3
end

defmodule Livekit.UpdateRoomMetadataRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :room, 1, type: :string
  field :metadata, 2, type: :string
end

defmodule Livekit.ListParticipantsRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :room, 1, type: :string
end

defmodule Livekit.ListParticipantsResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :participants, 1, repeated: true, type: Livekit.ParticipantInfo
end

defmodule Livekit.RoomParticipantIdentity do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :room, 1, type: :string
  field :identity, 2, type: :string
end

defmodule Livekit.RemoveParticipantResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3
end

defmodule Livekit.MuteRoomTrackRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :room, 1, type: :string
  field :identity, 2, type: :string
  field :track_sid, 3, type: :string, json_name: "trackSid"
  field :muted, 4, type: :bool
end

defmodule Livekit.MuteRoomTrackResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :track, 1, type: Livekit.TrackInfo
end

defmodule Livekit.UpdateParticipantRequest.AttributesEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Livekit.UpdateParticipantRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :room, 1, type: :string
  field :identity, 2, type: :string
  field :metadata, 3, type: :string
  field :permission, 4, type: Livekit.ParticipantPermission
  field :name, 5, type: :string

  field :attributes, 6,
    repeated: true,
    type: Livekit.UpdateParticipantRequest.AttributesEntry,
    map: true
end

defmodule Livekit.UpdateSubscriptionsRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :room, 1, type: :string
  field :identity, 2, type: :string
  field :track_sids, 3, repeated: true, type: :string, json_name: "trackSids"
  field :subscribe, 4, type: :bool
end

defmodule Livekit.UpdateSubscriptionsResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3
end

defmodule Livekit.SendDataRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :room, 1, type: :string
  field :data, 2, type: :bytes
  field :kind, 3, type: Livekit.DataPacketKind, enum: true
  field :destination_sids, 4, repeated: true, type: :string, json_name: "destinationSids"

  field :destination_identities, 5,
    repeated: true,
    type: :string,
    json_name: "destinationIdentities"

  field :nonce, 6, type: :bytes
end

defmodule Livekit.SendDataResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3
end

defmodule Livekit.CreateRoomRequest.TagsEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Livekit.CreateRoomRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:name, 1, type: :string)
  field(:room_preset, 12, type: :string, json_name: "roomPreset")
  field(:empty_timeout, 2, type: :uint32, json_name: "emptyTimeout")
  field(:departure_timeout, 10, type: :uint32, json_name: "departureTimeout")
  field(:max_participants, 3, type: :uint32, json_name: "maxParticipants")
  field(:node_id, 4, type: :string, json_name: "nodeId", deprecated: false)
  field(:metadata, 5, type: :string, deprecated: false)
  field(:tags, 15, repeated: true, type: Livekit.CreateRoomRequest.TagsEntry, map: true)
  field(:egress, 6, type: Livekit.RoomEgress)
  field(:min_playout_delay, 7, type: :uint32, json_name: "minPlayoutDelay")
  field(:max_playout_delay, 8, type: :uint32, json_name: "maxPlayoutDelay")
  field(:sync_streams, 9, type: :bool, json_name: "syncStreams")
  field(:replay_enabled, 13, type: :bool, json_name: "replayEnabled")
  field(:agents, 14, repeated: true, type: Livekit.RoomAgentDispatch)
end

defmodule Livekit.RoomEgress do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:room, 1, type: Livekit.RoomCompositeEgressRequest)
  field(:participant, 3, type: Livekit.AutoParticipantEgress)
  field(:tracks, 2, type: Livekit.AutoTrackEgress)
end

defmodule Livekit.RoomAgent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:dispatches, 1, repeated: true, type: Livekit.RoomAgentDispatch)
end

defmodule Livekit.ListRoomsRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:names, 1, repeated: true, type: :string)
end

defmodule Livekit.ListRoomsResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:rooms, 1, repeated: true, type: Livekit.Room)
end

defmodule Livekit.DeleteRoomRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:room, 1, type: :string)
end

defmodule Livekit.DeleteRoomResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3
end

defmodule Livekit.ListParticipantsRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:room, 1, type: :string)
end

defmodule Livekit.ListParticipantsResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:participants, 1, repeated: true, type: Livekit.ParticipantInfo)
end

defmodule Livekit.RoomParticipantIdentity do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:room, 1, type: :string)
  field(:identity, 2, type: :string)
  field(:revoke_token_ts, 3, type: :int64, json_name: "revokeTokenTs")
end

defmodule Livekit.RemoveParticipantResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3
end

defmodule Livekit.MuteRoomTrackRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:room, 1, type: :string)
  field(:identity, 2, type: :string)
  field(:track_sid, 3, type: :string, json_name: "trackSid")
  field(:muted, 4, type: :bool)
end

defmodule Livekit.MuteRoomTrackResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:track, 1, type: Livekit.TrackInfo)
end

defmodule Livekit.UpdateParticipantRequest.AttributesEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Livekit.UpdateParticipantRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:room, 1, type: :string)
  field(:identity, 2, type: :string)
  field(:metadata, 3, type: :string, deprecated: false)
  field(:permission, 4, type: Livekit.ParticipantPermission)
  field(:name, 5, type: :string, deprecated: false)

  field(:attributes, 6,
    repeated: true,
    type: Livekit.UpdateParticipantRequest.AttributesEntry,
    map: true,
    deprecated: false
  )
end

defmodule Livekit.UpdateSubscriptionsRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:room, 1, type: :string)
  field(:identity, 2, type: :string)
  field(:track_sids, 3, repeated: true, type: :string, json_name: "trackSids")
  field(:subscribe, 4, type: :bool)

  field(:participant_tracks, 5,
    repeated: true,
    type: Livekit.ParticipantTracks,
    json_name: "participantTracks"
  )
end

defmodule Livekit.UpdateSubscriptionsResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3
end

defmodule Livekit.SendDataRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:room, 1, type: :string)
  field(:data, 2, type: :bytes)
  field(:kind, 3, type: Livekit.DataPacket.Kind, enum: true)

  field(:destination_sids, 4,
    repeated: true,
    type: :string,
    json_name: "destinationSids",
    deprecated: true
  )

  field(:destination_identities, 6,
    repeated: true,
    type: :string,
    json_name: "destinationIdentities"
  )

  field(:topic, 5, proto3_optional: true, type: :string)
  field(:nonce, 7, type: :bytes)
end

defmodule Livekit.SendDataResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3
end

defmodule Livekit.UpdateRoomMetadataRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:room, 1, type: :string)
  field(:metadata, 2, type: :string, deprecated: false)
end

defmodule Livekit.RoomConfiguration.TagsEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Livekit.RoomConfiguration do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:name, 1, type: :string)
  field(:empty_timeout, 2, type: :uint32, json_name: "emptyTimeout")
  field(:departure_timeout, 3, type: :uint32, json_name: "departureTimeout")
  field(:max_participants, 4, type: :uint32, json_name: "maxParticipants")
  field(:metadata, 11, type: :string, deprecated: false)
  field(:egress, 5, type: Livekit.RoomEgress)
  field(:min_playout_delay, 7, type: :uint32, json_name: "minPlayoutDelay")
  field(:max_playout_delay, 8, type: :uint32, json_name: "maxPlayoutDelay")
  field(:sync_streams, 9, type: :bool, json_name: "syncStreams")
  field(:agents, 10, repeated: true, type: Livekit.RoomAgentDispatch)
  field(:tags, 12, repeated: true, type: Livekit.RoomConfiguration.TagsEntry, map: true)
end

defmodule Livekit.ForwardParticipantRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:room, 1, type: :string)
  field(:identity, 2, type: :string)
  field(:destination_room, 3, type: :string, json_name: "destinationRoom")
end

defmodule Livekit.ForwardParticipantResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3
end

defmodule Livekit.MoveParticipantRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:room, 1, type: :string)
  field(:identity, 2, type: :string)
  field(:destination_room, 3, type: :string, json_name: "destinationRoom")
end

defmodule Livekit.MoveParticipantResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3
end

defmodule Livekit.PerformRpcRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:room, 1, type: :string)
  field(:destination_identity, 2, type: :string, json_name: "destinationIdentity")
  field(:method, 3, type: :string)
  field(:payload, 4, type: :string)
  field(:response_timeout_ms, 5, type: :uint32, json_name: "responseTimeoutMs")
end

defmodule Livekit.PerformRpcResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:payload, 1, type: :string)
end

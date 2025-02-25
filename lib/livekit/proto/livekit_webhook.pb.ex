defmodule Livekit.WebhookEvent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field(:event, 1, type: :string)
  field(:room, 2, type: Livekit.Room)
  field(:participant, 3, type: Livekit.ParticipantInfo)
  field(:egress_info, 9, type: Livekit.EgressInfo, json_name: "egressInfo")
  field(:track, 8, type: Livekit.TrackInfo)
  field(:id, 6, type: :string)
  field(:created_at, 7, type: :int64, json_name: "createdAt")
  field(:num_dropped, 11, type: :int32, json_name: "numDropped")
end

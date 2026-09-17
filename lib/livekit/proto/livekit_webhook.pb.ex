defmodule Livekit.WebhookEvent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:event, 1, type: :string)
  field(:room, 2, type: Livekit.Room)
  field(:participant, 3, type: Livekit.ParticipantInfo)
  field(:egress_info, 9, type: Livekit.EgressInfo, json_name: "egressInfo")
  field(:ingress_info, 10, type: Livekit.IngressInfo, json_name: "ingressInfo")
  field(:track, 8, type: Livekit.TrackInfo)
  field(:job, 12, type: Livekit.Job)
  field(:id, 6, type: :string)
  field(:created_at, 7, type: :int64, json_name: "createdAt")
  field(:num_dropped, 11, type: :int32, json_name: "numDropped", deprecated: true)
  field(:room_end_reason, 13, type: Livekit.RoomEndReason, json_name: "roomEndReason", enum: true)
end

defmodule Livekit.RoomCompositeEgressRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :room_name, 1, type: :string, json_name: "roomName"
end

defmodule Livekit.AutoParticipantEgress do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :preset, 1, type: :string
end

defmodule Livekit.AutoTrackEgress do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :preset, 1, type: :string
end

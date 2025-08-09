defmodule Livekit.RoomAgentDispatch do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :name, 1, type: :string
  field :identity, 2, type: :string
  field :init_request, 3, type: Livekit.InitRequest, json_name: "initRequest"
end

defmodule Livekit.InitRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :prompt, 1, type: :string
end

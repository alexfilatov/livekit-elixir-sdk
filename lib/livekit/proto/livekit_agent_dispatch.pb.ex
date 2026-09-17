defmodule Livekit.JobRestartPolicy do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:JRP_ON_FAILURE, 0)
  field(:JRP_NEVER, 1)
end

defmodule Livekit.CreateAgentDispatchRequest.AttributesEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Livekit.CreateAgentDispatchRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:agent_name, 1, type: :string, json_name: "agentName")
  field(:room, 2, type: :string)
  field(:metadata, 3, type: :string, deprecated: false)

  field(:restart_policy, 4,
    type: Livekit.JobRestartPolicy,
    json_name: "restartPolicy",
    enum: true
  )

  field(:deployment, 5, type: :string)

  field(:attributes, 6,
    repeated: true,
    type: Livekit.CreateAgentDispatchRequest.AttributesEntry,
    map: true,
    deprecated: false
  )
end

defmodule Livekit.RoomAgentDispatch.AttributesEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Livekit.RoomAgentDispatch do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:agent_name, 1, type: :string, json_name: "agentName")
  field(:metadata, 2, type: :string, deprecated: false)

  field(:restart_policy, 3,
    type: Livekit.JobRestartPolicy,
    json_name: "restartPolicy",
    enum: true
  )

  field(:deployment, 4, type: :string)

  field(:attributes, 5,
    repeated: true,
    type: Livekit.RoomAgentDispatch.AttributesEntry,
    map: true,
    deprecated: false
  )
end

defmodule Livekit.DeleteAgentDispatchRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:dispatch_id, 1, type: :string, json_name: "dispatchId", deprecated: false)
  field(:room, 2, type: :string)
end

defmodule Livekit.ListAgentDispatchRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:dispatch_id, 1, type: :string, json_name: "dispatchId", deprecated: false)
  field(:room, 2, type: :string)
end

defmodule Livekit.ListAgentDispatchResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:agent_dispatches, 1,
    repeated: true,
    type: Livekit.AgentDispatch,
    json_name: "agentDispatches"
  )
end

defmodule Livekit.AgentDispatch.AttributesEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Livekit.AgentDispatch do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:id, 1, type: :string)
  field(:agent_name, 2, type: :string, json_name: "agentName")
  field(:room, 3, type: :string)
  field(:metadata, 4, type: :string, deprecated: false)
  field(:state, 5, type: Livekit.AgentDispatchState)

  field(:restart_policy, 6,
    type: Livekit.JobRestartPolicy,
    json_name: "restartPolicy",
    enum: true
  )

  field(:deployment, 7, type: :string)

  field(:attributes, 8,
    repeated: true,
    type: Livekit.AgentDispatch.AttributesEntry,
    map: true,
    deprecated: false
  )
end

defmodule Livekit.AgentDispatchState do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:jobs, 1, repeated: true, type: Livekit.Job)
  field(:created_at, 2, type: :int64, json_name: "createdAt")
  field(:deleted_at, 3, type: :int64, json_name: "deletedAt")
end

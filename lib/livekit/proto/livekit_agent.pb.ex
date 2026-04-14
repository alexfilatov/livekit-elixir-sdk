defmodule Livekit.JobType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :JT_ROOM, 0
  field :JT_PUBLISHER, 1
  field :JT_PARTICIPANT, 2
end

defmodule Livekit.WorkerStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :WS_AVAILABLE, 0
  field :WS_FULL, 1
end

defmodule Livekit.JobStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :JS_PENDING, 0
  field :JS_RUNNING, 1
  field :JS_SUCCESS, 2
  field :JS_FAILED, 3
end

defmodule Livekit.WorkerMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof :message, 0

  field :register, 1, type: Livekit.RegisterWorkerRequest, oneof: 0
  field :availability, 2, type: Livekit.AvailabilityResponse, oneof: 0
  field :update_worker, 3, type: Livekit.UpdateWorkerStatus, json_name: "updateWorker", oneof: 0
  field :update_job, 4, type: Livekit.UpdateJobStatus, json_name: "updateJob", oneof: 0
  field :ping, 5, type: Livekit.WorkerPing, oneof: 0
  field :simulate_job, 6, type: Livekit.SimulateJobRequest, json_name: "simulateJob", oneof: 0
  field :migrate_job, 7, type: Livekit.MigrateJobRequest, json_name: "migrateJob", oneof: 0
end

defmodule Livekit.ServerMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof :message, 0

  field :register, 1, type: Livekit.RegisterWorkerResponse, oneof: 0
  field :availability, 2, type: Livekit.AvailabilityRequest, oneof: 0
  field :assignment, 3, type: Livekit.JobAssignment, oneof: 0
  field :pong, 4, type: Livekit.WorkerPong, oneof: 0
  field :termination, 5, type: Livekit.JobTermination, oneof: 0
end

defmodule Livekit.Job do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :id, 1, type: :string
  field :dispatch_id, 9, type: :string, json_name: "dispatchId"
  field :type, 2, type: Livekit.JobType, enum: true
  field :room, 3, type: Livekit.Room
  field :participant, 4, proto3_optional: true, type: Livekit.ParticipantInfo
  field :metadata, 6, type: :string
  field :agent_name, 7, type: :string, json_name: "agentName"
  field :state, 8, type: Livekit.JobState
  field :enable_recording, 10, type: :bool, json_name: "enableRecording"
end

defmodule Livekit.JobState do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :status, 1, type: Livekit.JobStatus, enum: true
  field :error, 2, type: :string
  field :started_at, 3, type: :int64, json_name: "startedAt"
  field :ended_at, 4, type: :int64, json_name: "endedAt"
  field :updated_at, 5, type: :int64, json_name: "updatedAt"
  field :participant_identity, 6, type: :string, json_name: "participantIdentity"
  field :worker_id, 7, type: :string, json_name: "workerId"
  field :agent_id, 8, type: :string, json_name: "agentId"
end

defmodule Livekit.SimulateJobRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :type, 1, type: Livekit.JobType, enum: true
  field :room, 2, type: Livekit.Room
  field :participant, 3, type: Livekit.ParticipantInfo
end

defmodule Livekit.WorkerPing do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :timestamp, 1, type: :int64
end

defmodule Livekit.WorkerPong do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :last_timestamp, 1, type: :int64, json_name: "lastTimestamp"
  field :timestamp, 2, type: :int64
end

defmodule Livekit.RegisterWorkerRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :type, 1, type: Livekit.JobType, enum: true
  field :agent_name, 8, type: :string, json_name: "agentName"
  field :version, 3, type: :string
  field :ping_interval, 5, type: :uint32, json_name: "pingInterval"
  field :namespace, 6, proto3_optional: true, type: :string

  field :allowed_permissions, 7,
    type: Livekit.ParticipantPermission,
    json_name: "allowedPermissions"
end

defmodule Livekit.RegisterWorkerResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :worker_id, 1, type: :string, json_name: "workerId"
  field :server_info, 3, type: Livekit.ServerInfo, json_name: "serverInfo"
end

defmodule Livekit.MigrateJobRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :job_ids, 2, repeated: true, type: :string, json_name: "jobIds"
end

defmodule Livekit.AvailabilityRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :job, 1, type: Livekit.Job
  field :resuming, 2, type: :bool
end

defmodule Livekit.AvailabilityResponse.ParticipantAttributesEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Livekit.AvailabilityResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :job_id, 1, type: :string, json_name: "jobId"
  field :available, 2, type: :bool
  field :supports_resume, 3, type: :bool, json_name: "supportsResume"
  field :terminate, 8, type: :bool
  field :participant_name, 4, type: :string, json_name: "participantName"
  field :participant_identity, 5, type: :string, json_name: "participantIdentity"
  field :participant_metadata, 6, type: :string, json_name: "participantMetadata"

  field :participant_attributes, 7,
    repeated: true,
    type: Livekit.AvailabilityResponse.ParticipantAttributesEntry,
    json_name: "participantAttributes",
    map: true
end

defmodule Livekit.UpdateJobStatus do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :job_id, 1, type: :string, json_name: "jobId"
  field :status, 2, type: Livekit.JobStatus, enum: true
  field :error, 3, type: :string
end

defmodule Livekit.UpdateWorkerStatus do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :status, 1, proto3_optional: true, type: Livekit.WorkerStatus, enum: true
  field :load, 3, type: :float
  field :job_count, 4, type: :uint32, json_name: "jobCount"
end

defmodule Livekit.JobAssignment do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :job, 1, type: Livekit.Job
  field :url, 2, proto3_optional: true, type: :string
  field :token, 3, type: :string
end

defmodule Livekit.JobTermination do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :job_id, 1, type: :string, json_name: "jobId"
end

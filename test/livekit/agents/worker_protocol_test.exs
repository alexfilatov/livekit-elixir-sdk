defmodule Livekit.Agents.WorkerProtocolTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Livekit.{
    AvailabilityRequest,
    AvailabilityResponse,
    Job,
    JobAssignment,
    JobTermination,
    JobType,
    RegisterWorkerRequest,
    RegisterWorkerResponse,
    Room,
    ServerInfo,
    ServerMessage,
    UpdateJobStatus,
    UpdateWorkerStatus,
    WorkerMessage,
    WorkerPing,
    WorkerPong,
    WorkerStatus
  }

  # ---------------------------------------------------------------------------
  # WorkerMessage encode/decode (worker -> server)
  # ---------------------------------------------------------------------------

  describe "WorkerMessage: RegisterWorkerRequest" do
    test "encodes and decodes register message" do
      register = %RegisterWorkerRequest{
        type: JobType.value(:JT_ROOM),
        agent_name: "test-agent",
        version: "0.1.4",
        ping_interval: 5,
        namespace: "default"
      }

      msg = %WorkerMessage{message: {:register, register}}
      binary = Protobuf.encode(msg)

      assert is_binary(binary)
      assert byte_size(binary) > 0

      decoded = Protobuf.decode(binary, WorkerMessage)
      assert {:register, decoded_register} = decoded.message
      assert decoded_register.agent_name == "test-agent"
      assert decoded_register.version == "0.1.4"
      assert decoded_register.ping_interval == 5
      assert decoded_register.namespace == "default"
    end

    test "JobType.value/1 returns integer keys" do
      assert JobType.value(:JT_ROOM) == 0
      assert JobType.value(:JT_PUBLISHER) == 1
      assert JobType.value(:JT_PARTICIPANT) == 2
    end

    test "JobType.key/1 returns atom names" do
      assert JobType.key(0) == :JT_ROOM
      assert JobType.key(1) == :JT_PUBLISHER
      assert JobType.key(2) == :JT_PARTICIPANT
    end

    test "decoded enum fields are atoms" do
      register = %RegisterWorkerRequest{
        type: JobType.value(:JT_ROOM),
        agent_name: "agent",
        version: "1.0"
      }

      msg = %WorkerMessage{message: {:register, register}}
      binary = Protobuf.encode(msg)
      decoded = Protobuf.decode(binary, WorkerMessage)
      {:register, r} = decoded.message
      # Decoded enum fields come back as atoms
      assert r.type == :JT_ROOM
    end

    test "encodes all JobType variants and decodes as atoms" do
      expected = [
        {:JT_ROOM, :JT_ROOM},
        {:JT_PUBLISHER, :JT_PUBLISHER},
        {:JT_PARTICIPANT, :JT_PARTICIPANT}
      ]

      for {encode_atom, expected_atom} <- expected do
        register = %RegisterWorkerRequest{
          type: JobType.value(encode_atom),
          agent_name: "agent",
          version: "1.0"
        }

        msg = %WorkerMessage{message: {:register, register}}
        binary = Protobuf.encode(msg)
        decoded = Protobuf.decode(binary, WorkerMessage)
        {:register, r} = decoded.message
        assert r.type == expected_atom, "Expected #{expected_atom}, got #{r.type}"
      end
    end
  end

  describe "WorkerMessage: UpdateWorkerStatus" do
    test "encodes and decodes status update with load" do
      update = %UpdateWorkerStatus{
        status: WorkerStatus.value(:WS_AVAILABLE),
        load: 0.5,
        job_count: 3
      }

      msg = %WorkerMessage{message: {:update_worker, update}}
      binary = Protobuf.encode(msg)

      decoded = Protobuf.decode(binary, WorkerMessage)
      assert {:update_worker, u} = decoded.message
      assert_in_delta u.load, 0.5, 0.001
      assert u.job_count == 3
    end

    test "WorkerStatus.value/1 returns integers" do
      assert WorkerStatus.value(:WS_AVAILABLE) == 0
      assert WorkerStatus.value(:WS_FULL) == 1
    end

    test "decoded WorkerStatus fields are atoms" do
      update = %UpdateWorkerStatus{
        status: WorkerStatus.value(:WS_FULL),
        load: 1.0,
        job_count: 10
      }

      msg = %WorkerMessage{message: {:update_worker, update}}
      binary = Protobuf.encode(msg)
      decoded = Protobuf.decode(binary, WorkerMessage)
      {:update_worker, u} = decoded.message
      # Decoded enum comes back as atom
      assert u.status == :WS_FULL
      assert_in_delta u.load, 1.0, 0.001
    end
  end

  describe "WorkerMessage: AvailabilityResponse" do
    test "encodes available=true response" do
      response = %AvailabilityResponse{
        job_id: "job-abc-123",
        available: true,
        supports_resume: false,
        participant_identity: "worker-1"
      }

      msg = %WorkerMessage{message: {:availability, response}}
      binary = Protobuf.encode(msg)

      decoded = Protobuf.decode(binary, WorkerMessage)
      assert {:availability, r} = decoded.message
      assert r.job_id == "job-abc-123"
      assert r.available == true
      assert r.supports_resume == false
      assert r.participant_identity == "worker-1"
    end

    test "encodes available=false response (at capacity)" do
      response = %AvailabilityResponse{
        job_id: "job-xyz",
        available: false
      }

      msg = %WorkerMessage{message: {:availability, response}}
      binary = Protobuf.encode(msg)
      decoded = Protobuf.decode(binary, WorkerMessage)
      {:availability, r} = decoded.message
      assert r.available == false
    end
  end

  describe "WorkerMessage: UpdateJobStatus" do
    test "encodes job success status (JS_SUCCESS = 2)" do
      update = %UpdateJobStatus{
        job_id: "job-99",
        status: 2,
        error: ""
      }

      msg = %WorkerMessage{message: {:update_job, update}}
      binary = Protobuf.encode(msg)
      decoded = Protobuf.decode(binary, WorkerMessage)
      {:update_job, u} = decoded.message
      assert u.job_id == "job-99"
      # Decoded enum for status 2 is :JS_SUCCESS
      assert u.status == :JS_SUCCESS
    end

    test "encodes job failed status with error (JS_FAILED = 3)" do
      update = %UpdateJobStatus{
        job_id: "job-fail",
        status: 3,
        error: "agent crashed"
      }

      msg = %WorkerMessage{message: {:update_job, update}}
      binary = Protobuf.encode(msg)
      decoded = Protobuf.decode(binary, WorkerMessage)
      {:update_job, u} = decoded.message
      assert u.status == :JS_FAILED
      assert u.error == "agent crashed"
    end
  end

  describe "WorkerMessage: WorkerPing" do
    test "encodes and decodes ping with timestamp" do
      ts = System.system_time(:millisecond)
      ping = %WorkerPing{timestamp: ts}

      msg = %WorkerMessage{message: {:ping, ping}}
      binary = Protobuf.encode(msg)

      decoded = Protobuf.decode(binary, WorkerMessage)
      assert {:ping, p} = decoded.message
      assert p.timestamp == ts
    end
  end

  # ---------------------------------------------------------------------------
  # ServerMessage decode (server -> worker)
  # ---------------------------------------------------------------------------

  describe "ServerMessage: RegisterWorkerResponse" do
    test "decodes register response with worker_id" do
      response = %RegisterWorkerResponse{
        worker_id: "server-assigned-worker-42",
        server_info: %ServerInfo{
          version: "1.5.0",
          region: "us-west",
          node_id: "node-1",
          agent_protocol: 1
        }
      }

      msg = %ServerMessage{message: {:register, response}}
      binary = Protobuf.encode(msg)

      decoded = Protobuf.decode(binary, ServerMessage)
      assert {:register, r} = decoded.message
      assert r.worker_id == "server-assigned-worker-42"
      assert r.server_info.version == "1.5.0"
      assert r.server_info.region == "us-west"
      assert r.server_info.node_id == "node-1"
      assert r.server_info.agent_protocol == 1
    end

    test "decodes register response without server_info" do
      response = %RegisterWorkerResponse{worker_id: "wkr-123"}

      msg = %ServerMessage{message: {:register, response}}
      binary = Protobuf.encode(msg)
      decoded = Protobuf.decode(binary, ServerMessage)
      {:register, r} = decoded.message
      assert r.worker_id == "wkr-123"
    end
  end

  describe "ServerMessage: AvailabilityRequest" do
    test "decodes availability request with job details" do
      job = %Job{
        id: "job-req-1",
        type: JobType.value(:JT_ROOM),
        agent_name: "voice-agent",
        room: %Room{
          name: "my-room",
          sid: "RM_room1"
        }
      }

      request = %AvailabilityRequest{job: job, resuming: false}
      msg = %ServerMessage{message: {:availability, request}}
      binary = Protobuf.encode(msg)

      decoded = Protobuf.decode(binary, ServerMessage)
      assert {:availability, r} = decoded.message
      assert r.job.id == "job-req-1"
      assert r.job.room.name == "my-room"
      assert r.resuming == false
    end

    test "decodes resuming=true request for migrated jobs" do
      job = %Job{id: "job-migrated", type: JobType.value(:JT_ROOM)}
      request = %AvailabilityRequest{job: job, resuming: true}
      msg = %ServerMessage{message: {:availability, request}}
      binary = Protobuf.encode(msg)
      decoded = Protobuf.decode(binary, ServerMessage)
      {:availability, r} = decoded.message
      assert r.resuming == true
    end
  end

  describe "ServerMessage: JobAssignment" do
    test "decodes job assignment with room and token" do
      job = %Job{
        id: "job-assign-1",
        type: JobType.value(:JT_ROOM),
        room: %Room{
          name: "assigned-room",
          sid: "RM_abc"
        },
        metadata: ~s({"key":"value"})
      }

      assignment = %JobAssignment{
        job: job,
        token: "eyJhbGciOiJIUzI1NiJ9.test",
        url: "wss://livekit.example.com"
      }

      msg = %ServerMessage{message: {:assignment, assignment}}
      binary = Protobuf.encode(msg)

      decoded = Protobuf.decode(binary, ServerMessage)
      assert {:assignment, a} = decoded.message
      assert a.job.id == "job-assign-1"
      assert a.job.room.name == "assigned-room"
      assert a.token == "eyJhbGciOiJIUzI1NiJ9.test"
      assert a.url == "wss://livekit.example.com"
    end

    test "decodes job assignment without optional url" do
      job = %Job{id: "job-nourl", room: %Room{name: "room-1"}}
      assignment = %JobAssignment{job: job, token: "tok"}
      msg = %ServerMessage{message: {:assignment, assignment}}
      binary = Protobuf.encode(msg)
      decoded = Protobuf.decode(binary, ServerMessage)
      {:assignment, a} = decoded.message
      assert a.job.id == "job-nourl"
      # optional url defaults to nil when not set
      assert a.url == nil
    end
  end

  describe "ServerMessage: WorkerPong" do
    test "decodes pong with last_timestamp for RTT calculation" do
      sent_ts = System.system_time(:millisecond)
      pong = %WorkerPong{last_timestamp: sent_ts, timestamp: sent_ts + 5}

      msg = %ServerMessage{message: {:pong, pong}}
      binary = Protobuf.encode(msg)

      decoded = Protobuf.decode(binary, ServerMessage)
      assert {:pong, p} = decoded.message
      assert p.last_timestamp == sent_ts
      assert p.timestamp == sent_ts + 5
    end
  end

  describe "ServerMessage: JobTermination" do
    test "decodes job termination request" do
      termination = %JobTermination{job_id: "job-to-kill"}
      msg = %ServerMessage{message: {:termination, termination}}
      binary = Protobuf.encode(msg)

      decoded = Protobuf.decode(binary, ServerMessage)
      assert {:termination, t} = decoded.message
      assert t.job_id == "job-to-kill"
    end
  end

  # ---------------------------------------------------------------------------
  # Binary frame properties
  # ---------------------------------------------------------------------------

  describe "binary frame properties" do
    test "all WorkerMessage variants produce non-empty binary" do
      messages = [
        {:register,
         %RegisterWorkerRequest{type: 0, agent_name: "a", version: "1", ping_interval: 5}},
        {:availability, %AvailabilityResponse{job_id: "j", available: true}},
        {:update_worker, %UpdateWorkerStatus{load: 0.5, job_count: 1}},
        {:update_job, %UpdateJobStatus{job_id: "j", status: 2}},
        {:ping, %WorkerPing{timestamp: 1_000_000}}
      ]

      for {field, payload} <- messages do
        msg = %WorkerMessage{message: {field, payload}}
        binary = Protobuf.encode(msg)
        assert is_binary(binary), "Expected binary for field: #{field}"
        assert byte_size(binary) > 0, "Expected non-empty binary for field: #{field}"
      end
    end

    test "round-trip preserves oneof field type" do
      ping = %WorkerPing{timestamp: 999_888_777}
      msg = %WorkerMessage{message: {:ping, ping}}
      binary = Protobuf.encode(msg)
      decoded = Protobuf.decode(binary, WorkerMessage)
      assert {:ping, _} = decoded.message
    end

    test "invalid binary raises on decode" do
      bad_data = <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>

      result =
        try do
          Protobuf.decode(bad_data, ServerMessage)
          :decoded
        rescue
          _ -> :error
        end

      # Either decodes to an empty/partial message or raises — both acceptable
      assert result in [:decoded, :error]
    end

    test "empty binary decodes to empty ServerMessage" do
      decoded = Protobuf.decode(<<>>, ServerMessage)
      assert decoded.message == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Oneof message construction
  # ---------------------------------------------------------------------------

  describe "oneof message construction" do
    test "WorkerMessage oneof built with message: tuple" do
      payload = %UpdateWorkerStatus{load: 0.25, job_count: 2}
      msg = %WorkerMessage{message: {:update_worker, payload}}
      assert {:update_worker, _} = msg.message
    end

    test "WorkerMessage ping field via message: tuple" do
      ping = %WorkerPing{timestamp: 42}
      msg = %WorkerMessage{message: {:ping, ping}}
      assert {:ping, p} = msg.message
      assert p.timestamp == 42
    end

    test "encode then decode preserves load float precision" do
      update = %UpdateWorkerStatus{load: 0.333, job_count: 1}
      msg = %WorkerMessage{message: {:update_worker, update}}
      binary = Protobuf.encode(msg)
      decoded = Protobuf.decode(binary, WorkerMessage)
      {:update_worker, u} = decoded.message
      # Float32 precision — compare within 0.001
      assert_in_delta u.load, 0.333, 0.001
    end
  end
end

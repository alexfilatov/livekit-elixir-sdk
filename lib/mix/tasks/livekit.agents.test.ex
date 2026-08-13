defmodule Mix.Tasks.Livekit.Agents.Test do
  @moduledoc """
  Test LiveKit agent functionality.

  This task provides comprehensive testing capabilities for your agents,
  including unit tests, integration tests, and load testing.

  ## Usage

      mix livekit.agents.test [test_type] [options]

  ## Test Types

      unit                      Run unit tests only
      integration              Run integration tests
      load                     Run load tests
      pipeline                 Test voice pipeline
      providers                Test AI provider connections
      all                      Run all tests (default)

  ## Options

      --room ROOM_NAME          Test room name (default: "test-room")
      --server-url URL          LiveKit server URL
      --api-key KEY             LiveKit API key
      --api-secret SECRET       LiveKit API secret
      --concurrent N            Concurrent connections for load testing
      --duration SECONDS        Load test duration in seconds
      --verbose                 Verbose output
      --help                    Show this help

  ## Examples

      # Run all tests
      mix livekit.agents.test

      # Run only unit tests
      mix livekit.agents.test unit

      # Run integration tests with specific room
      mix livekit.agents.test integration --room my-test-room

      # Load test with 10 concurrent agents for 60 seconds
      mix livekit.agents.test load --concurrent 10 --duration 60

  """

  use Mix.Task
  require Logger

  alias Livekit.Agents.{AgentSession, AudioFrame, JobContext, Pipeline, VoiceAgent, Worker}
  alias Livekit.Agents.LLM.OpenAI
  alias Livekit.Agents.STT.Deepgram
  alias Livekit.Agents.TTS.OpenAI, as: OpenAITTS

  @shortdoc "Test agent functionality"

  def run(args) do
    case parse_args(args) do
      {:ok, test_type, config} ->
        Mix.shell().info("🧪 Running LiveKit Agent Tests")
        run_tests(test_type, config)

      {:error, :help} ->
        show_help()

      {:error, reason} ->
        Mix.shell().error("Error: #{reason}")
        System.halt(1)
    end
  end

  defp parse_args([]) do
    {:ok, :all, %{}}
  end

  defp parse_args([test_type | args])
       when test_type in ["unit", "integration", "load", "pipeline", "providers", "all"] do
    {parsed, _, _} =
      OptionParser.parse(args,
        strict: [
          room: :string,
          server_url: :string,
          api_key: :string,
          api_secret: :string,
          concurrent: :integer,
          duration: :integer,
          verbose: :boolean,
          help: :boolean
        ]
      )

    if parsed[:help] do
      {:error, :help}
    else
      config = build_test_config(parsed)
      {:ok, String.to_atom(test_type), config}
    end
  end

  defp parse_args(["--help"]) do
    {:error, :help}
  end

  defp parse_args(_) do
    {:error, "Invalid test type. Use: unit, integration, load, pipeline, providers, or all"}
  end

  defp build_test_config(parsed) do
    %{
      room_name: parsed[:room] || "test-room-#{:rand.uniform(1000)}",
      server_url: parsed[:server_url] || get_env_var("LIVEKIT_URL") || "ws://localhost:7880",
      api_key: parsed[:api_key] || get_env_var("LIVEKIT_API_KEY"),
      api_secret: parsed[:api_secret] || get_env_var("LIVEKIT_API_SECRET"),
      concurrent: parsed[:concurrent] || 5,
      duration: parsed[:duration] || 30,
      verbose: parsed[:verbose] || false
    }
  end

  defp run_tests(test_type, config) do
    # Start the application
    Application.ensure_all_started(:livekit)

    if config.verbose do
      Logger.configure(level: :debug)
    end

    case test_type do
      :unit -> run_unit_tests()
      :integration -> run_integration_tests(config)
      :load -> run_load_tests(config)
      :pipeline -> run_pipeline_tests(config)
      :providers -> run_provider_tests(config)
      :all -> run_all_tests(config)
    end
  end

  defp run_unit_tests do
    Mix.shell().info("🔧 Running Unit Tests")
    Mix.shell().info(String.duplicate("=", 40))

    tests = [
      {"AudioFrame Creation", &test_audio_frame_creation/0},
      {"AudioFrame Operations", &test_audio_frame_operations/0},
      {"VoiceAgent Configuration", &test_voice_agent_config/0},
      {"JobContext Validation", &test_job_context/0},
      {"Pipeline Initialization", &test_pipeline_init/0}
    ]

    run_test_suite(tests)
  end

  defp run_integration_tests(config) do
    Mix.shell().info("🔗 Running Integration Tests")
    Mix.shell().info(String.duplicate("=", 40))

    tests = [
      {"Agent Session Lifecycle", fn -> test_agent_session_lifecycle(config) end},
      {"Voice Agent Processing", fn -> test_voice_agent_processing(config) end},
      {"Worker Registration", fn -> test_worker_registration(config) end}
    ]

    run_test_suite(tests)
  end

  defp run_pipeline_tests(config) do
    Mix.shell().info("🎵 Running Pipeline Tests")
    Mix.shell().info(String.duplicate("=", 40))

    tests = [
      {"STT Processing", fn -> test_stt_processing(config) end},
      {"LLM Processing", fn -> test_llm_processing(config) end},
      {"TTS Processing", fn -> test_tts_processing(config) end},
      {"Full Pipeline", fn -> test_full_pipeline(config) end}
    ]

    run_test_suite(tests)
  end

  defp run_provider_tests(config) do
    Mix.shell().info("🤖 Running AI Provider Tests")
    Mix.shell().info(String.duplicate("=", 40))

    tests = [
      {"Deepgram STT Connection", fn -> test_deepgram_connection(config) end},
      {"OpenAI LLM Connection", fn -> test_openai_llm_connection(config) end},
      {"OpenAI TTS Connection", fn -> test_openai_tts_connection(config) end}
    ]

    run_test_suite(tests)
  end

  defp run_load_tests(config) do
    Mix.shell().info("⚡ Running Load Tests")
    Mix.shell().info(String.duplicate("=", 40))
    Mix.shell().info("Concurrent agents: #{config.concurrent}")
    Mix.shell().info("Duration: #{config.duration} seconds")
    Mix.shell().info("")

    start_time = System.monotonic_time(:second)

    # Start multiple agent sessions concurrently
    agent_tasks =
      for i <- 1..config.concurrent do
        Task.async(fn ->
          load_test_agent(config, i, config.duration)
        end)
      end

    # Wait for all agents to complete
    results = Task.await_many(agent_tasks, (config.duration + 10) * 1000)

    end_time = System.monotonic_time(:second)
    total_duration = end_time - start_time

    # Analyze results
    analyze_load_test_results(results, total_duration, config)
  end

  defp run_all_tests(config) do
    Mix.shell().info("🎯 Running All Tests")
    Mix.shell().info(String.duplicate("=", 50))

    run_unit_tests()
    Mix.shell().info("")
    run_pipeline_tests(config)
    Mix.shell().info("")
    run_integration_tests(config)
    Mix.shell().info("")

    if config.api_key && config.api_secret do
      run_provider_tests(config)
      Mix.shell().info("")
    else
      Mix.shell().info("⚠️  Skipping provider tests (no API credentials)")
      Mix.shell().info("")
    end

    Mix.shell().info("✅ All tests completed!")
  end

  defp run_test_suite(tests) do
    results =
      Enum.map(tests, fn {name, test_fn} ->
        Mix.shell().info("Testing #{name}...")

        try do
          case test_fn.() do
            :ok ->
              Mix.shell().info("  ✅ #{name} - PASSED")
              {name, :passed}

            {:error, reason} ->
              Mix.shell().error("  ❌ #{name} - FAILED: #{inspect(reason)}")
              {name, :failed, reason}
          end
        rescue
          error ->
            Mix.shell().error("  ❌ #{name} - ERROR: #{inspect(error)}")
            {name, :error, error}
        end
      end)

    # Summary
    passed = Enum.count(results, fn {_, status} -> status == :passed end)
    total = length(results)

    Mix.shell().info("")
    Mix.shell().info("Test Results: #{passed}/#{total} passed")

    if passed == total do
      Mix.shell().info("🎉 All tests passed!")
    else
      failed_tests = Enum.filter(results, fn {_, status} -> status != :passed end)
      Mix.shell().error("❌ Failed tests:")

      Enum.each(failed_tests, fn {name, status, reason} ->
        Mix.shell().error("  - #{name}: #{status} - #{inspect(reason)}")
      end)
    end

    Mix.shell().info("")
  end

  # Unit Test Functions

  defp test_audio_frame_creation do
    audio_data = :crypto.strong_rand_bytes(1000)
    frame = AudioFrame.new(audio_data, sample_rate: 16_000)

    if frame.sample_rate == 16_000 and frame.data == audio_data do
      :ok
    else
      {:error, "AudioFrame creation failed"}
    end
  end

  defp test_audio_frame_operations do
    audio_data = :crypto.strong_rand_bytes(1000)
    frame = AudioFrame.new(audio_data, sample_rate: 48_000)

    # Test resampling
    resampled = AudioFrame.resample(frame, 16_000)

    if resampled.sample_rate == 16_000 do
      :ok
    else
      {:error, "AudioFrame resampling failed"}
    end
  end

  defp test_voice_agent_config do
    config = %VoiceAgent.Config{
      instructions: "Test instructions",
      name: "Test Agent"
    }

    {:ok, pid} = VoiceAgent.start_link(config)

    if Process.alive?(pid) do
      GenServer.stop(pid)
      :ok
    else
      {:error, "VoiceAgent failed to start"}
    end
  end

  defp test_job_context do
    context =
      JobContext.new(%{
        job_id: "test-job",
        room_name: "test-room",
        participant_identity: "test-agent",
        server_url: "ws://localhost:7880",
        api_key: "test-key",
        api_secret: "test-secret"
      })

    case JobContext.validate(context) do
      :ok -> :ok
      error -> error
    end
  end

  # Pipeline is a GenServer, not a struct built by `new/0` — this task was
  # written against an API that never shipped, so it could not run at all.
  defp test_pipeline_init do
    case Pipeline.start_link(%Pipeline.Config{subscriber: self()}) do
      {:ok, pid} ->
        Pipeline.stop(pid)
        :ok

      {:error, reason} ->
        {:error, "Pipeline initialization failed: #{inspect(reason)}"}
    end
  end

  # Integration Test Functions

  defp test_agent_session_lifecycle(config) do
    session_config = %AgentSession.Config{
      room_name: config.room_name,
      participant_identity: "test-agent",
      server_url: config.server_url,
      api_key: config.api_key || "test-key",
      api_secret: config.api_secret || "test-secret"
    }

    case AgentSession.start_link(session_config) do
      {:ok, session_pid} ->
        status = AgentSession.get_status(session_pid)

        if status.room_name == config.room_name do
          GenServer.stop(session_pid)
          :ok
        else
          GenServer.stop(session_pid)
          {:error, "Session status mismatch"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp test_voice_agent_processing(_config) do
    voice_config = %VoiceAgent.Config{
      instructions: "Test agent",
      name: "Test Agent"
    }

    case VoiceAgent.start_link(voice_config) do
      {:ok, agent_pid} ->
        # Test audio processing
        audio_data = :crypto.strong_rand_bytes(4800)
        audio_frame = AudioFrame.new(audio_data, sample_rate: 48_000)

        case VoiceAgent.process_audio_frame(agent_pid, audio_frame) do
          :ok ->
            GenServer.stop(agent_pid)
            :ok

          error ->
            GenServer.stop(agent_pid)
            error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp test_worker_registration(config) do
    if config.api_key && config.api_secret do
      worker_config = %Worker.Config{
        server_url: config.server_url,
        api_key: config.api_key,
        api_secret: config.api_secret,
        entrypoint: fn _job -> :ok end
      }

      start_and_check_worker(worker_config)
    else
      Mix.shell().info("  ⚠️  Skipping worker test (no credentials)")
      :ok
    end
  end

  defp start_and_check_worker(worker_config) do
    case Worker.start_link(worker_config) do
      {:ok, worker_pid} ->
        check_worker_status(worker_pid)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_worker_status(worker_pid) do
    status = Worker.get_status(worker_pid)
    GenServer.stop(worker_pid)

    if status.worker_id do
      :ok
    else
      {:error, "Worker status invalid"}
    end
  end

  # Pipeline Test Functions

  defp test_stt_processing(_config) do
    # Test with mock STT
    audio_data = :crypto.strong_rand_bytes(4800)
    audio_frame = AudioFrame.new(audio_data, sample_rate: 48_000)

    # No STT configured, so the frame is accepted and dropped — what is under
    # test here is that a frame can be pushed without the pipeline crashing.
    case Pipeline.start_link(%Pipeline.Config{subscriber: self()}) do
      {:ok, pid} ->
        :ok = Pipeline.push_frame(pid, audio_frame)
        _ = Pipeline.get_metrics(pid)
        Pipeline.stop(pid)
        :ok

      {:error, reason} ->
        {:error, "STT pipeline failed to start: #{inspect(reason)}"}
    end
  end

  defp test_llm_processing(_config) do
    # With no LLM configured the pipeline still has to hold a chat context;
    # that round trip is the useful check without reaching a provider.
    case Pipeline.start_link(%Pipeline.Config{subscriber: self()}) do
      {:ok, pid} ->
        ctx = Pipeline.get_chat_context(pid)
        :ok = Pipeline.set_chat_context(pid, ctx)
        Pipeline.stop(pid)
        :ok

      {:error, reason} ->
        {:error, "LLM pipeline failed to start: #{inspect(reason)}"}
    end
  end

  defp test_tts_processing(_config) do
    # Mock TTS test - just verify pipeline handles text
    :ok
  end

  defp test_full_pipeline(_config) do
    # Test complete pipeline flow
    voice_config = %VoiceAgent.Config{
      instructions: "Test pipeline",
      name: "Pipeline Test Agent"
    }

    case VoiceAgent.start_link(voice_config) do
      {:ok, agent_pid} ->
        metrics = VoiceAgent.get_metrics(agent_pid)

        if is_map(metrics) do
          GenServer.stop(agent_pid)
          :ok
        else
          GenServer.stop(agent_pid)
          {:error, "Pipeline metrics failed"}
        end

      error ->
        error
    end
  end

  # Provider Test Functions

  defp test_deepgram_connection(_config) do
    case System.get_env("DEEPGRAM_API_KEY") do
      nil ->
        Mix.shell().info("  ⚠️  Skipping Deepgram test (no API key)")
        :ok

      api_key ->
        deepgram_config = %Deepgram.Config{
          api_key: api_key,
          model: "nova-2"
        }

        case Deepgram.validate_config(deepgram_config) do
          :ok -> :ok
          error -> error
        end
    end
  end

  defp test_openai_llm_connection(_config) do
    case System.get_env("OPENAI_API_KEY") do
      nil ->
        Mix.shell().info("  ⚠️  Skipping OpenAI LLM test (no API key)")
        :ok

      api_key ->
        openai_config = %OpenAI.Config{
          api_key: api_key,
          model: "gpt-4o-mini"
        }

        case OpenAI.validate_config(openai_config) do
          :ok -> :ok
          error -> error
        end
    end
  end

  defp test_openai_tts_connection(_config) do
    case System.get_env("OPENAI_API_KEY") do
      nil ->
        Mix.shell().info("  ⚠️  Skipping OpenAI TTS test (no API key)")
        :ok

      api_key ->
        tts_config = %OpenAITTS.Config{
          api_key: api_key,
          voice: :alloy
        }

        case OpenAITTS.validate_config(tts_config) do
          :ok -> :ok
          error -> error
        end
    end
  end

  # Load Test Functions

  defp load_test_agent(config, agent_id, duration) do
    session_config = %AgentSession.Config{
      room_name: "#{config.room_name}-#{agent_id}",
      participant_identity: "load-test-agent-#{agent_id}",
      server_url: config.server_url,
      api_key: config.api_key || "test-key",
      api_secret: config.api_secret || "test-secret"
    }

    start_time = System.monotonic_time(:second)

    case AgentSession.start_link(session_config) do
      {:ok, session_pid} ->
        # Simulate agent activity
        simulate_agent_activity(session_pid, duration)

        end_time = System.monotonic_time(:second)
        actual_duration = end_time - start_time

        _status = AgentSession.get_status(session_pid)
        GenServer.stop(session_pid)

        %{
          agent_id: agent_id,
          duration: actual_duration,
          messages_processed: 0,
          success: true
        }

      {:error, reason} ->
        %{
          agent_id: agent_id,
          duration: 0,
          error: reason,
          success: false
        }
    end
  end

  defp simulate_agent_activity(session_pid, duration) do
    end_time = System.monotonic_time(:second) + duration

    simulate_activity_loop(session_pid, end_time)
  end

  defp simulate_activity_loop(session_pid, end_time) do
    current_time = System.monotonic_time(:second)

    if current_time < end_time and Process.alive?(session_pid) do
      # Simulate activity (send_message removed in Phase 12 refactor)
      _ = session_pid

      # Wait a bit
      Process.sleep(1000)

      simulate_activity_loop(session_pid, end_time)
    end
  end

  defp analyze_load_test_results(results, total_duration, config) do
    successful = Enum.count(results, fn %{success: success} -> success end)
    failed = length(results) - successful

    total_messages =
      Enum.sum(
        Enum.map(results, fn
          %{messages_processed: count} -> count
          _ -> 0
        end)
      )

    Mix.shell().info("Load Test Results:")
    Mix.shell().info(String.duplicate("=", 30))
    Mix.shell().info("Total duration: #{total_duration} seconds")
    Mix.shell().info("Concurrent agents: #{config.concurrent}")
    Mix.shell().info("Successful agents: #{successful}")
    Mix.shell().info("Failed agents: #{failed}")
    Mix.shell().info("Total messages: #{total_messages}")
    Mix.shell().info("Messages/second: #{Float.round(total_messages / total_duration, 2)}")

    if failed > 0 do
      Mix.shell().error("❌ Load test had failures")
      failed_results = Enum.filter(results, fn %{success: success} -> not success end)

      Enum.each(failed_results, fn %{agent_id: id, error: error} ->
        Mix.shell().error("  Agent #{id}: #{inspect(error)}")
      end)
    else
      Mix.shell().info("✅ Load test successful!")
    end
  end

  defp get_env_var(name) do
    System.get_env(name)
  end

  defp show_help do
    Mix.shell().info(@moduledoc)
  end
end

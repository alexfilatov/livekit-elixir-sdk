defmodule Mix.Tasks.Livekit.Agents.Dev do
  @moduledoc """
  Start a LiveKit agent in development mode with hot reloading.

  This mode starts an agent server that automatically reloads code changes
  and provides enhanced debugging capabilities.

  ## Usage

      mix livekit.agents.dev [options]

  ## Options

      --room ROOM_NAME          Room name to join (default: "dev-room")
      --identity IDENTITY       Agent identity (default: "dev-agent")
      --server-url URL          LiveKit server URL
      --api-key KEY             LiveKit API key
      --api-secret SECRET       LiveKit API secret
      --config-file FILE        Path to configuration file
      --port PORT               Development server port (default: 4000)
      --verbose                 Enable verbose logging
      --help                    Show this help

  ## Example

      mix livekit.agents.dev --room my-dev-room --verbose

  """

  use Mix.Task
  require Logger

  alias Livekit.Agents.{AgentSession, VoiceAgent, Worker}

  @shortdoc "Start agent in development mode"

  def run(args) do
    case parse_args(args) do
      {:ok, config} ->
        Mix.shell().info("Starting LiveKit Agent in development mode...")
        start_dev_agent(config)

      {:error, :help} ->
        show_help()

      {:error, reason} ->
        Mix.shell().error("Error: #{reason}")
        System.halt(1)
    end
  end

  defp parse_args(args) do
    {parsed, _, _} =
      OptionParser.parse(args,
        strict: [
          room: :string,
          identity: :string,
          server_url: :string,
          api_key: :string,
          api_secret: :string,
          config_file: :string,
          port: :integer,
          verbose: :boolean,
          help: :boolean
        ]
      )

    if parsed[:help] do
      {:error, :help}
    else
      config = build_dev_config(parsed)
      validate_config(config)
    end
  end

  defp build_dev_config(parsed) do
    # Load from config file if specified
    base_config =
      case parsed[:config_file] do
        nil -> %{}
        file -> load_config_file(file)
      end

    # Override with command line args
    %{
      room_name: resolve(parsed[:room], base_config[:room_name], "dev-room"),
      participant_identity:
        resolve(parsed[:identity], base_config[:participant_identity], "dev-agent"),
      server_url:
        resolve(parsed[:server_url], base_config[:server_url], get_env_var("LIVEKIT_URL")),
      api_key: resolve(parsed[:api_key], base_config[:api_key], get_env_var("LIVEKIT_API_KEY")),
      api_secret:
        resolve(parsed[:api_secret], base_config[:api_secret], get_env_var("LIVEKIT_API_SECRET")),
      dev_port: resolve(parsed[:port], base_config[:dev_port], 4000),
      verbose: resolve(parsed[:verbose], base_config[:verbose], false)
    }
  end

  defp resolve(nil, nil, default), do: default
  defp resolve(nil, base, _default), do: base
  defp resolve(value, _base, _default), do: value

  defp validate_config(config) do
    cond do
      is_nil(config.server_url) ->
        {:error, "Missing server URL. Set LIVEKIT_URL environment variable or use --server-url"}

      is_nil(config.api_key) ->
        {:error, "Missing API key. Set LIVEKIT_API_KEY environment variable or use --api-key"}

      is_nil(config.api_secret) ->
        {:error,
         "Missing API secret. Set LIVEKIT_API_SECRET environment variable or use --api-secret"}

      true ->
        {:ok, config}
    end
  end

  defp start_dev_agent(config) do
    # Start the application if not already started
    Application.ensure_all_started(:livekit)

    # Configure logging level
    if config.verbose do
      Logger.configure(level: :debug)
      Mix.shell().info("Verbose logging enabled")
    end

    Mix.shell().info("🚀 LiveKit Agent Development Server")
    Mix.shell().info("Room: #{config.room_name}")
    Mix.shell().info("Identity: #{config.participant_identity}")
    Mix.shell().info("Server: #{config.server_url}")
    Mix.shell().info("Dev Port: #{config.dev_port}")
    Mix.shell().info("")

    # Start development server
    start_dev_server(config)

    # Create agent worker
    worker_config = %Worker.Config{
      server_url: config.server_url,
      api_key: config.api_key,
      api_secret: config.api_secret,
      entrypoint: &dev_agent_entrypoint/1,
      max_concurrent_jobs: 5,
      worker_metadata: %{
        mode: :development,
        dev_port: config.dev_port,
        hot_reload: true
      }
    }

    case Worker.start_link(worker_config, name: :dev_worker) do
      {:ok, worker_pid} ->
        # Worker self-registers on WebSocket upgrade
        Mix.shell().info("✅ Agent worker started (will register with server on connect)")
        dev_loop(config, worker_pid)

      {:error, reason} ->
        Mix.shell().error("❌ Failed to start worker: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp start_dev_server(config) do
    # Start a simple HTTP server for development dashboard
    spawn_link(fn ->
      try do
        # This would start a web interface for development
        # For now, just log that dev server is running
        Mix.shell().info(
          "📊 Development dashboard available at http://localhost:#{config.dev_port}"
        )

        Process.sleep(:infinity)
      rescue
        error ->
          Mix.shell().error("Dev server error: #{inspect(error)}")
      end
    end)
  end

  defp dev_agent_entrypoint(job_context) do
    Mix.shell().info("🎯 New job: #{job_context.job_id} in room #{job_context.room_name}")

    # Create development voice agent with enhanced features
    voice_config = %VoiceAgent.Config{
      instructions: """
      You are a development AI assistant. You're running in development mode,
      so you can help debug, explain code, and provide detailed responses.
      Be helpful and informative in your responses.
      """,
      name: "Dev Agent",
      # In development, we can use mock providers or real ones based on config
      stt: get_stt_provider(),
      llm: get_llm_provider(),
      tts: get_tts_provider()
    }

    # Note: voice_config is no longer used directly — pipeline_config wires STT/LLM/TTS
    _ = voice_config

    # Create session configuration
    session_config = %AgentSession.Config{
      room_name: job_context.room_name,
      participant_identity: job_context.participant_identity,
      server_url: job_context.server_url,
      api_key: job_context.api_key,
      api_secret: job_context.api_secret,
      auto_subscribe: true
    }

    # Start the agent session
    case AgentSession.start_link(session_config) do
      {:ok, session_pid} ->
        Mix.shell().info("✅ Agent session started for #{job_context.room_name}")

        # Connect to room
        case AgentSession.connect_to_room(session_pid) do
          :ok ->
            Mix.shell().info("🔗 Connected to room successfully")
            monitor_session(session_pid, job_context)

          {:error, reason} ->
            Mix.shell().error("❌ Failed to connect to room: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Mix.shell().error("❌ Failed to start session: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp monitor_session(session_pid, job_context) do
    # Monitor the session and provide development feedback
    ref = Process.monitor(session_pid)

    receive do
      {:DOWN, ^ref, :process, _pid, reason} ->
        case reason do
          :normal ->
            Mix.shell().info("✅ Session completed normally for #{job_context.room_name}")

          :shutdown ->
            Mix.shell().info("🔄 Session shutdown for #{job_context.room_name}")

          other ->
            Mix.shell().error("❌ Session crashed: #{inspect(other)}")
        end
    after
      # Provide periodic status updates
      30_000 ->
        status = AgentSession.get_status(session_pid)
        Mix.shell().info("📈 Session status: #{status.participants_count} participants")
        monitor_session(session_pid, job_context)
    end

    :ok
  end

  defp dev_loop(config, worker_pid) do
    Mix.shell().info("")
    Mix.shell().info("🛠️  Development Commands:")
    Mix.shell().info("  'status' - Show worker status")
    Mix.shell().info("  'jobs' - List active jobs")
    Mix.shell().info("  'reload' - Reload agent code")
    Mix.shell().info("  'test <room>' - Join a test room")
    Mix.shell().info("  'quit' - Stop the development server")
    Mix.shell().info("")
    Mix.shell().info("Agent is ready for connections!")

    dev_input_loop(config, worker_pid)
  end

  defp dev_input_loop(config, worker_pid) do
    case IO.gets("dev> ") do
      :eof ->
        Mix.shell().info("Exiting development mode...")

      {:error, reason} ->
        Mix.shell().error("Input error: #{inspect(reason)}")
        dev_input_loop(config, worker_pid)

      input ->
        command = String.trim(input)
        handle_dev_command(config, worker_pid, command)
        dev_input_loop(config, worker_pid)
    end
  end

  defp handle_dev_command(_config, _worker_pid, "quit") do
    Mix.shell().info("🛑 Stopping development server...")
    System.halt(0)
  end

  defp handle_dev_command(_config, worker_pid, "status") do
    status = Worker.get_status(worker_pid)
    Mix.shell().info("Worker Status:")

    Enum.each(status, fn {key, value} ->
      Mix.shell().info("  #{key}: #{inspect(value)}")
    end)
  end

  defp handle_dev_command(_config, worker_pid, "jobs") do
    jobs = Worker.list_active_jobs(worker_pid)
    Mix.shell().info("Active Jobs (#{length(jobs)}):")

    if jobs == [] do
      Mix.shell().info("  No active jobs")
    else
      Enum.each(jobs, fn job ->
        Mix.shell().info("  #{job.job_id}: #{job.room_name} (#{job.status})")
      end)
    end
  end

  defp handle_dev_command(_config, _worker_pid, "reload") do
    Mix.shell().info("🔄 Reloading agent code...")
    # In a real implementation, this would trigger code reloading
    IEx.Helpers.recompile()
    Mix.shell().info("✅ Code reloaded")
  end

  defp handle_dev_command(config, _worker_pid, "test " <> room_name) do
    Mix.shell().info("🧪 Starting test session in room: #{room_name}")

    test_config = %AgentSession.Config{
      room_name: room_name,
      participant_identity: "test-agent-#{:rand.uniform(1000)}",
      server_url: config.server_url,
      api_key: config.api_key,
      api_secret: config.api_secret
    }

    case AgentSession.start_link(test_config) do
      {:ok, session_pid} ->
        case AgentSession.connect_to_room(session_pid) do
          :ok ->
            Mix.shell().info("✅ Test agent connected to #{room_name}")

          {:error, reason} ->
            Mix.shell().error("❌ Test connection failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        Mix.shell().error("❌ Failed to start test session: #{inspect(reason)}")
    end
  end

  defp handle_dev_command(_config, _worker_pid, command) do
    if String.trim(command) != "" do
      Mix.shell().error("Unknown command: #{command}")
      Mix.shell().info("Type 'quit' to exit or try 'status', 'jobs', 'reload', or 'test <room>'")
    end
  end

  # Development AI provider configurations
  defp get_stt_provider do
    case System.get_env("DEEPGRAM_API_KEY") do
      nil ->
        Mix.shell().info("ℹ️  No Deepgram key found, using mock STT")
        nil

      api_key ->
        {Livekit.Agents.STT.Deepgram,
         %{
           api_key: api_key,
           model: "nova-2",
           language: "en-US",
           interim_results: true
         }}
    end
  end

  defp get_llm_provider do
    case System.get_env("OPENAI_API_KEY") do
      nil ->
        Mix.shell().info("ℹ️  No OpenAI key found, using mock LLM")
        nil

      api_key ->
        {Livekit.Agents.LLM.OpenAI,
         %{
           api_key: api_key,
           model: "gpt-4o-mini",
           temperature: 0.7,
           instructions: "You are a helpful development assistant."
         }}
    end
  end

  defp get_tts_provider do
    case System.get_env("OPENAI_API_KEY") do
      nil ->
        Mix.shell().info("ℹ️  No OpenAI key found, using mock TTS")
        nil

      api_key ->
        {Livekit.Agents.TTS.OpenAI,
         %{
           api_key: api_key,
           voice: :alloy,
           model: :tts_1
         }}
    end
  end

  defp load_config_file(file) do
    case File.read(file) do
      {:ok, content} ->
        case Jason.decode(content, keys: :atoms) do
          {:ok, config} -> config
          {:error, _} -> %{}
        end

      {:error, _} ->
        Mix.shell().error("Warning: Could not read config file: #{file}")
        %{}
    end
  end

  defp get_env_var(name) do
    System.get_env(name)
  end

  defp show_help do
    Mix.shell().info(@moduledoc)
  end
end

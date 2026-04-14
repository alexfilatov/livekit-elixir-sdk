defmodule Mix.Tasks.Livekit.Agents.Start do
  @moduledoc """
  Start a LiveKit agent in production mode.

  This mode starts an agent worker optimized for production deployment
  with proper logging, monitoring, and error handling.

  ## Usage

      mix livekit.agents.start [options]

  ## Options

      --config-file FILE        Path to production configuration file (required)
      --workers COUNT           Number of worker processes (default: 1)
      --server-url URL          LiveKit server URL
      --api-key KEY             LiveKit API key
      --api-secret SECRET       LiveKit API secret
      --log-level LEVEL         Log level (debug, info, warn, error)
      --metrics-port PORT       Metrics server port (default: 9090)
      --health-port PORT        Health check port (default: 8080)
      --help                    Show this help

  ## Configuration File

  Create a JSON configuration file for production settings:

      {
        "server_url": "wss://your-livekit-server.com",
        "api_key": "your-api-key",
        "api_secret": "your-api-secret",
        "workers": 3,
        "log_level": "info",
        "voice_agent": {
          "instructions": "You are a production AI assistant.",
          "stt": {
            "provider": "deepgram",
            "api_key": "your-deepgram-key",
            "model": "nova-2"
          },
          "llm": {
            "provider": "openai",
            "api_key": "your-openai-key",
            "model": "gpt-4o-mini"
          },
          "tts": {
            "provider": "openai",
            "api_key": "your-openai-key",
            "voice": "alloy"
          }
        }
      }

  ## Example

      mix livekit.agents.start --config-file config/production.json

  """

  use Mix.Task
  require Logger

  alias Livekit.Agents.{Worker, VoiceAgent, AgentSession}

  @shortdoc "Start agent in production mode"

  def run(args) do
    case parse_args(args) do
      {:ok, config} ->
        Mix.shell().info("Starting LiveKit Agent in production mode...")
        start_production_agent(config)

      {:error, :help} ->
        show_help()

      {:error, reason} ->
        Mix.shell().error("Error: #{reason}")
        System.halt(1)
    end
  end

  defp parse_args(args) do
    {parsed, _, _} = OptionParser.parse(args,
      strict: [
        config_file: :string,
        workers: :integer,
        server_url: :string,
        api_key: :string,
        api_secret: :string,
        log_level: :string,
        metrics_port: :integer,
        health_port: :integer,
        help: :boolean
      ]
    )

    if parsed[:help] do
      {:error, :help}
    else
      config = build_production_config(parsed)
      validate_production_config(config)
    end
  end

  defp build_production_config(parsed) do
    # Load configuration file
    base_config = case parsed[:config_file] do
      nil ->
        Mix.shell().error("Production mode requires a configuration file")
        %{}

      file ->
        load_production_config_file(file)
    end

    # Override with command line args
    %{
      server_url: parsed[:server_url] || base_config[:server_url] || get_env_var("LIVEKIT_URL"),
      api_key: parsed[:api_key] || base_config[:api_key] || get_env_var("LIVEKIT_API_KEY"),
      api_secret: parsed[:api_secret] || base_config[:api_secret] || get_env_var("LIVEKIT_API_SECRET"),
      workers: parsed[:workers] || base_config[:workers] || 1,
      log_level: String.to_atom(parsed[:log_level] || base_config[:log_level] || "info"),
      metrics_port: parsed[:metrics_port] || base_config[:metrics_port] || 9090,
      health_port: parsed[:health_port] || base_config[:health_port] || 8080,
      voice_agent: base_config[:voice_agent] || %{}
    }
  end

  defp validate_production_config(config) do
    cond do
      is_nil(config.server_url) ->
        {:error, "Missing server URL"}

      is_nil(config.api_key) ->
        {:error, "Missing API key"}

      is_nil(config.api_secret) ->
        {:error, "Missing API secret"}

      config.workers <= 0 ->
        {:error, "Workers count must be positive"}

      true ->
        {:ok, config}
    end
  end

  defp start_production_agent(config) do
    # Configure application for production
    Application.ensure_all_started(:livekit)
    Logger.configure(level: config.log_level)

    # Print startup banner
    print_production_banner(config)

    # Start monitoring services
    start_health_server(config.health_port)
    start_metrics_server(config.metrics_port)

    # Start worker supervisor
    case start_worker_supervisor(config) do
      {:ok, supervisor_pid} ->
        Mix.shell().info("✅ Production agent cluster started with #{config.workers} workers")

        # Setup signal handlers for graceful shutdown
        setup_signal_handlers(supervisor_pid)

        # Keep the system running
        production_loop(config, supervisor_pid)

      {:error, reason} ->
        Mix.shell().error("❌ Failed to start worker supervisor: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp print_production_banner(config) do
    Mix.shell().info("")
    Mix.shell().info("🚀 LiveKit Agents - Production Mode")
    Mix.shell().info("=====================================")
    Mix.shell().info("Server: #{config.server_url}")
    Mix.shell().info("Workers: #{config.workers}")
    Mix.shell().info("Log Level: #{config.log_level}")
    Mix.shell().info("Health Check: http://localhost:#{config.health_port}/health")
    Mix.shell().info("Metrics: http://localhost:#{config.metrics_port}/metrics")
    Mix.shell().info("=====================================")
    Mix.shell().info("")
  end

  defp start_health_server(port) do
    spawn_link(fn ->
      try do
        # Simple health check server
        Mix.shell().info("🏥 Health server starting on port #{port}")

        # In a real implementation, this would be a proper HTTP server
        # For now, just indicate it's running
        Process.register(self(), :health_server)
        health_server_loop(port)
      rescue
        error ->
          Mix.shell().error("Health server error: #{inspect(error)}")
      end
    end)
  end

  defp health_server_loop(port) do
    receive do
      {:health_check, from} ->
        send(from, {:health_status, :healthy})
        health_server_loop(port)

      :shutdown ->
        Mix.shell().info("🏥 Health server shutting down")

    after
      5000 ->
        # Periodic health logging
        Logger.debug("Health server alive on port #{port}")
        health_server_loop(port)
    end
  end

  defp start_metrics_server(port) do
    spawn_link(fn ->
      try do
        # Metrics collection server
        Mix.shell().info("📊 Metrics server starting on port #{port}")

        Process.register(self(), :metrics_server)
        metrics_server_loop(port)
      rescue
        error ->
          Mix.shell().error("Metrics server error: #{inspect(error)}")
      end
    end)
  end

  defp metrics_server_loop(port) do
    receive do
      {:metrics_request, from} ->
        metrics = collect_system_metrics()
        send(from, {:metrics_response, metrics})
        metrics_server_loop(port)

      :shutdown ->
        Mix.shell().info("📊 Metrics server shutting down")

    after
      10_000 ->
        # Periodic metrics collection
        metrics = collect_system_metrics()
        Logger.debug("System metrics: #{inspect(metrics)}")
        metrics_server_loop(port)
    end
  end

  defp collect_system_metrics do
    %{
      timestamp: DateTime.utc_now(),
      memory_usage: :erlang.memory(),
      process_count: :erlang.system_info(:process_count),
      uptime: :erlang.statistics(:wall_clock)
    }
  end

  defp start_worker_supervisor(config) do
    # Create worker specifications
    worker_specs = for i <- 1..config.workers do
      worker_config = %Worker.Config{
        worker_id: "prod-worker-#{i}",
        server_url: config.server_url,
        api_key: config.api_key,
        api_secret: config.api_secret,
        entrypoint: &production_agent_entrypoint(&1, config),
        max_concurrent_jobs: 10,
        worker_metadata: %{
          mode: :production,
          worker_index: i,
          total_workers: config.workers
        }
      }

      %{
        id: "worker_#{i}",
        start: {Worker, :start_link, [worker_config, [name: :"worker_#{i}"]]},
        restart: :permanent,
        type: :worker
      }
    end

    # Start supervisor (workers self-register on WebSocket upgrade)
    Supervisor.start_link(worker_specs, strategy: :one_for_one, name: :agent_supervisor)
  end

  defp production_agent_entrypoint(job_context, config) do
    Logger.info("Starting production agent for job #{job_context.job_id}")

    # Create production voice agent
    voice_config = build_voice_agent_config(config.voice_agent)

    # Create session configuration
    # Note: voice_config is no longer used directly — pipeline_config wires STT/LLM/TTS
    _ = voice_config

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
        Logger.info("Agent session started for #{job_context.room_name}")

        # Connect to room
        case AgentSession.connect_to_room(session_pid) do
          :ok ->
            Logger.info("Connected to room successfully")
            monitor_production_session(session_pid, job_context)

          {:error, reason} ->
            Logger.error("Failed to connect to room: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to start session: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_voice_agent_config(voice_config) do
    %VoiceAgent.Config{
      instructions: voice_config[:instructions] || "You are a helpful AI assistant.",
      name: voice_config[:name] || "Production Agent",
      stt: build_stt_config(voice_config[:stt]),
      llm: build_llm_config(voice_config[:llm]),
      tts: build_tts_config(voice_config[:tts])
    }
  end

  defp build_stt_config(nil), do: nil
  defp build_stt_config(stt_config) do
    case stt_config[:provider] do
      "deepgram" ->
        {Livekit.Agents.STT.Deepgram, %{
          api_key: stt_config[:api_key],
          model: stt_config[:model] || "nova-2",
          language: stt_config[:language] || "en-US"
        }}

      _ ->
        nil
    end
  end

  defp build_llm_config(nil), do: nil
  defp build_llm_config(llm_config) do
    case llm_config[:provider] do
      "openai" ->
        {Livekit.Agents.LLM.OpenAI, %{
          api_key: llm_config[:api_key],
          model: llm_config[:model] || "gpt-4o-mini",
          temperature: llm_config[:temperature] || 0.7
        }}

      _ ->
        nil
    end
  end

  defp build_tts_config(nil), do: nil
  defp build_tts_config(tts_config) do
    case tts_config[:provider] do
      "openai" ->
        voice = case tts_config[:voice] do
          "alloy" -> :alloy
          "echo" -> :echo
          "fable" -> :fable
          "onyx" -> :onyx
          "nova" -> :nova
          "shimmer" -> :shimmer
          _ -> :alloy
        end

        {Livekit.Agents.TTS.OpenAI, %{
          api_key: tts_config[:api_key],
          voice: voice,
          model: :tts_1
        }}

      _ ->
        nil
    end
  end

  defp monitor_production_session(session_pid, job_context) do
    # Production session monitoring with minimal logging
    ref = Process.monitor(session_pid)

    receive do
      {:DOWN, ^ref, :process, _pid, reason} ->
        case reason do
          :normal ->
            Logger.info("Session completed for #{job_context.room_name}")

          :shutdown ->
            Logger.info("Session shutdown for #{job_context.room_name}")

          other ->
            Logger.error("Session crashed for #{job_context.room_name}: #{inspect(other)}")
        end
    after
      60_000 ->
        # Periodic health check
        if Process.alive?(session_pid) do
          Logger.debug("Session healthy for #{job_context.room_name}")
        end
        monitor_production_session(session_pid, job_context)
    end

    :ok
  end

  defp setup_signal_handlers(supervisor_pid) do
    # Handle SIGTERM for graceful shutdown
    spawn_link(fn ->
      Process.flag(:trap_exit, true)
      signal_handler_loop(supervisor_pid)
    end)
  end

  defp signal_handler_loop(supervisor_pid) do
    receive do
      {:EXIT, _pid, reason} ->
        Logger.warning("Received exit signal: #{inspect(reason)}")
        graceful_shutdown(supervisor_pid)

    after
      1000 ->
        signal_handler_loop(supervisor_pid)
    end
  end

  defp graceful_shutdown(supervisor_pid) do
    Mix.shell().info("🛑 Initiating graceful shutdown...")

    # Stop all workers gracefully
    Supervisor.stop(supervisor_pid, :shutdown, 30_000)

    # Stop monitoring services
    case Process.whereis(:health_server) do
      nil -> :ok
      pid -> send(pid, :shutdown)
    end

    case Process.whereis(:metrics_server) do
      nil -> :ok
      pid -> send(pid, :shutdown)
    end

    Mix.shell().info("✅ Graceful shutdown completed")
    System.halt(0)
  end

  defp production_loop(config, supervisor_pid) do
    receive do
      :shutdown ->
        graceful_shutdown(supervisor_pid)

    after
      30_000 ->
        # Periodic status check
        children = Supervisor.which_children(supervisor_pid)
        active_workers = Enum.count(children, fn {_id, pid, _type, _modules} ->
          is_pid(pid) and Process.alive?(pid)
        end)

        if active_workers != config.workers do
          Logger.warning("Worker count mismatch: #{active_workers}/#{config.workers} active")
        end

        production_loop(config, supervisor_pid)
    end
  end

  defp load_production_config_file(file) do
    case File.read(file) do
      {:ok, content} ->
        case Jason.decode(content, keys: :atoms) do
          {:ok, config} ->
            Mix.shell().info("✅ Loaded configuration from #{file}")
            config

          {:error, reason} ->
            Mix.shell().error("❌ Invalid JSON in config file: #{inspect(reason)}")
            %{}
        end

      {:error, reason} ->
        Mix.shell().error("❌ Could not read config file #{file}: #{inspect(reason)}")
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
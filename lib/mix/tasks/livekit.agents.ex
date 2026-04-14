defmodule Mix.Tasks.Livekit.Agents do
  @moduledoc """
  Mix tasks for LiveKit agent development and management.

  Available commands:

  - `mix livekit.agents.console` - Start an agent in console mode for testing
  - `mix livekit.agents.dev` - Start an agent server with hot reloading
  - `mix livekit.agents.start` - Start an agent in production mode
  - `mix livekit.agents.create` - Create a new agent template
  - `mix livekit.agents.test` - Test agent functionality
  """

  use Mix.Task

  @shortdoc "LiveKit agent development tools"

  def run(["console" | args]) do
    Mix.Tasks.Livekit.Agents.Console.run(args)
  end

  def run(["dev" | args]) do
    Mix.Tasks.Livekit.Agents.Dev.run(args)
  end

  def run(["start" | args]) do
    Mix.Tasks.Livekit.Agents.Start.run(args)
  end

  def run(["create" | args]) do
    Mix.Tasks.Livekit.Agents.Create.run(args)
  end

  def run(["test" | args]) do
    Mix.Tasks.Livekit.Agents.Test.run(args)
  end

  def run([]) do
    show_help()
  end

  def run(["--help"]) do
    show_help()
  end

  def run([command | _]) when command in ["--help", "-h", "help"] do
    show_help()
  end

  def run([command | _]) do
    Mix.shell().error("Unknown command: #{command}")
    show_help()
  end

  defp show_help do
    Mix.shell().info("LiveKit Agents - Available commands:")
    Mix.shell().info("")
    Mix.shell().info("  mix livekit.agents.console    Start agent in console mode")
    Mix.shell().info("  mix livekit.agents.dev        Start agent server with hot reloading")
    Mix.shell().info("  mix livekit.agents.start      Start agent in production mode")
    Mix.shell().info("  mix livekit.agents.create     Create a new agent template")
    Mix.shell().info("  mix livekit.agents.test       Test agent functionality")
    Mix.shell().info("")
    Mix.shell().info("Use --help with any command for more information.")
  end
end

defmodule Mix.Tasks.Livekit.Agents.Console do
  @moduledoc """
  Start a LiveKit agent in console mode for testing.

  This mode allows you to test your agent locally with audio input/output
  through your computer's microphone and speakers.

  ## Usage

      mix livekit.agents.console [options]

  ## Options

      --room ROOM_NAME          Room name to join (default: "test-room")
      --identity IDENTITY       Agent identity (default: "console-agent")
      --server-url URL          LiveKit server URL
      --api-key KEY             LiveKit API key
      --api-secret SECRET       LiveKit API secret
      --config-file FILE        Path to configuration file
      --help                    Show this help

  ## Example

      mix livekit.agents.console --room my-room --identity my-agent

  """

  use Mix.Task
  require Logger

  alias Livekit.Agents.{Worker, VoiceAgent, AgentSession}

  @shortdoc "Start agent in console mode"

  def run(args) do
    case parse_args(args) do
      {:ok, config} ->
        Mix.shell().info("Starting LiveKit Agent in console mode...")
        start_console_agent(config)

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
        room: :string,
        identity: :string,
        server_url: :string,
        api_key: :string,
        api_secret: :string,
        config_file: :string,
        help: :boolean
      ]
    )

    if parsed[:help] do
      {:error, :help}
    else
      config = build_config(parsed)
      validate_config(config)
    end
  end

  defp build_config(parsed) do
    # Load from config file if specified
    base_config = case parsed[:config_file] do
      nil -> %{}
      file -> load_config_file(file)
    end

    # Override with command line args
    %{
      room_name: parsed[:room] || base_config[:room_name] || "test-room",
      participant_identity: parsed[:identity] || base_config[:participant_identity] || "console-agent",
      server_url: parsed[:server_url] || base_config[:server_url] || get_env_var("LIVEKIT_URL"),
      api_key: parsed[:api_key] || base_config[:api_key] || get_env_var("LIVEKIT_API_KEY"),
      api_secret: parsed[:api_secret] || base_config[:api_secret] || get_env_var("LIVEKIT_API_SECRET")
    }
  end

  defp validate_config(config) do
    cond do
      is_nil(config.server_url) ->
        {:error, "Missing server URL. Set LIVEKIT_URL environment variable or use --server-url"}

      is_nil(config.api_key) ->
        {:error, "Missing API key. Set LIVEKIT_API_KEY environment variable or use --api-key"}

      is_nil(config.api_secret) ->
        {:error, "Missing API secret. Set LIVEKIT_API_SECRET environment variable or use --api-secret"}

      true ->
        {:ok, config}
    end
  end

  defp start_console_agent(config) do
    # Start the application if not already started
    Application.ensure_all_started(:livekit)

    Mix.shell().info("Connecting to room: #{config.room_name}")
    Mix.shell().info("Agent identity: #{config.participant_identity}")
    Mix.shell().info("Server: #{config.server_url}")

    # Create voice agent configuration
    voice_config = %VoiceAgent.Config{
      instructions: """
      You are a helpful AI assistant running in console mode.
      You can hear the user through their microphone and respond through their speakers.
      Keep your responses concise and friendly.
      """,
      name: "Console Agent",
      # These would be configured with real API keys in production
      stt: nil,
      llm: nil,
      tts: nil
    }

    # Create session configuration
    session_config = %AgentSession.Config{
      room_name: config.room_name,
      participant_identity: config.participant_identity,
      server_url: config.server_url,
      api_key: config.api_key,
      api_secret: config.api_secret,
      voice_agent_config: voice_config
    }

    # Start the agent session
    case AgentSession.start_link(session_config) do
      {:ok, session_pid} ->
        Mix.shell().info("Agent started successfully!")
        Mix.shell().info("Press Ctrl+C to stop the agent")

        # Connect to room
        case AgentSession.connect_to_room(session_pid) do
          :ok ->
            Mix.shell().info("Connected to room successfully!")
            console_loop(session_pid)

          {:error, reason} ->
            Mix.shell().error("Failed to connect to room: #{inspect(reason)}")
            System.halt(1)
        end

      {:error, reason} ->
        Mix.shell().error("Failed to start agent: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp console_loop(session_pid) do
    Mix.shell().info("\nAgent is running. Available commands:")
    Mix.shell().info("  'status' - Show agent status")
    Mix.shell().info("  'participants' - List participants")
    Mix.shell().info("  'say <message>' - Send a message")
    Mix.shell().info("  'quit' - Stop the agent")
    Mix.shell().info("")

    console_input_loop(session_pid)
  end

  defp console_input_loop(session_pid) do
    case IO.gets("> ") do
      :eof ->
        Mix.shell().info("Exiting...")

      {:error, reason} ->
        Mix.shell().error("Input error: #{inspect(reason)}")
        console_input_loop(session_pid)

      input ->
        command = String.trim(input)
        handle_console_command(session_pid, command)
        console_input_loop(session_pid)
    end
  end

  defp handle_console_command(session_pid, "quit") do
    Mix.shell().info("Stopping agent...")
    AgentSession.disconnect_from_room(session_pid)
    System.halt(0)
  end

  defp handle_console_command(session_pid, "status") do
    status = AgentSession.get_status(session_pid)
    Mix.shell().info("Agent Status:")
    Enum.each(status, fn {key, value} ->
      Mix.shell().info("  #{key}: #{inspect(value)}")
    end)
  end

  defp handle_console_command(session_pid, "participants") do
    participants = AgentSession.list_participants(session_pid)
    Mix.shell().info("Participants (#{length(participants)}):")
    Enum.each(participants, fn participant ->
      Mix.shell().info("  - #{participant.identity}")
    end)
  end

  defp handle_console_command(session_pid, "say " <> message) do
    case AgentSession.send_message(session_pid, message) do
      :ok ->
        Mix.shell().info("Message sent: #{message}")

      {:error, reason} ->
        Mix.shell().error("Failed to send message: #{inspect(reason)}")
    end
  end

  defp handle_console_command(_session_pid, command) do
    if String.trim(command) != "" do
      Mix.shell().error("Unknown command: #{command}")
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

defmodule Mix.Tasks.Livekit.Agents.Create do
  @moduledoc """
  Create a new LiveKit agent template.

  ## Usage

      mix livekit.agents.create [agent_name] [options]

  ## Options

      --path PATH              Directory to create the agent in
      --template TEMPLATE      Template type (basic, advanced, voice)
      --help                   Show this help

  ## Example

      mix livekit.agents.create my_agent --template voice

  """

  use Mix.Task
  require Logger

  @shortdoc "Create a new agent template"

  def run(args) do
    case parse_args(args) do
      {:ok, agent_name, config} ->
        create_agent_template(agent_name, config)

      {:error, :help} ->
        show_help()

      {:error, reason} ->
        Mix.shell().error("Error: #{reason}")
        System.halt(1)
    end
  end

  defp parse_args([agent_name | args]) when is_binary(agent_name) do
    {parsed, _, _} = OptionParser.parse(args,
      strict: [
        path: :string,
        template: :string,
        help: :boolean
      ]
    )

    if parsed[:help] do
      {:error, :help}
    else
      config = %{
        path: parsed[:path] || ".",
        template: String.to_atom(parsed[:template] || "basic")
      }
      {:ok, agent_name, config}
    end
  end

  defp parse_args(["--help"]) do
    {:error, :help}
  end

  defp parse_args(_) do
    {:error, "Agent name is required"}
  end

  defp create_agent_template(agent_name, config) do
    agent_dir = Path.join(config.path, agent_name)

    if File.exists?(agent_dir) do
      Mix.shell().error("Directory #{agent_dir} already exists")
      System.halt(1)
    end

    Mix.shell().info("Creating agent: #{agent_name}")
    Mix.shell().info("Template: #{config.template}")
    Mix.shell().info("Path: #{agent_dir}")

    File.mkdir_p!(agent_dir)

    case config.template do
      :basic -> create_basic_template(agent_dir, agent_name)
      :voice -> create_voice_template(agent_dir, agent_name)
      :advanced -> create_advanced_template(agent_dir, agent_name)
      _ ->
        Mix.shell().error("Unknown template: #{config.template}")
        System.halt(1)
    end

    Mix.shell().info("Agent created successfully!")
    Mix.shell().info("To run your agent:")
    Mix.shell().info("  cd #{agent_dir}")
    Mix.shell().info("  mix livekit.agents.console")
  end

  defp create_basic_template(agent_dir, agent_name) do
    # Create basic agent file
    agent_content = """
    defmodule #{Macro.camelize(agent_name)} do
      @moduledoc \"\"\"
      Basic LiveKit agent implementation.
      \"\"\"

      alias Livekit.Agents.{Worker, AgentSession, VoiceAgent, JobContext}

      def main do
        # Configure your agent
        config = %Worker.Config{
          server_url: System.get_env("LIVEKIT_URL"),
          api_key: System.get_env("LIVEKIT_API_KEY"),
          api_secret: System.get_env("LIVEKIT_API_SECRET"),
          entrypoint: &agent_entrypoint/1
        }

        # Start the worker
        {:ok, worker_pid} = Worker.start_link(config)
        Worker.register_worker(worker_pid)

        # Keep the process alive
        Process.sleep(:infinity)
      end

      defp agent_entrypoint(job_context) do
        # This function is called for each job
        IO.puts("Agent started for room: \#{job_context.room_name}")

        # Your agent logic goes here
        :ok
      end
    end
    """

    File.write!(Path.join(agent_dir, "#{agent_name}.ex"), agent_content)

    # Create mix.exs
    mix_content = """
    defmodule #{Macro.camelize(agent_name)}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{agent_name},
          version: "0.1.0",
          elixir: "~> 1.15",
          start_permanent: Mix.env() == :prod,
          deps: deps()
        ]
      end

      def application do
        [
          extra_applications: [:logger]
        ]
      end

      defp deps do
        [
          {:livekit, path: ".."}  # Adjust path to your livekit dependency
        ]
      end
    end
    """

    File.write!(Path.join(agent_dir, "mix.exs"), mix_content)

    # Create README
    readme_content = """
    # #{String.capitalize(agent_name)}

    A basic LiveKit agent.

    ## Setup

    1. Set environment variables:
       ```
       export LIVEKIT_URL="ws://localhost:7880"
       export LIVEKIT_API_KEY="your-api-key"
       export LIVEKIT_API_SECRET="your-api-secret"
       ```

    2. Install dependencies:
       ```
       mix deps.get
       ```

    3. Run the agent:
       ```
       mix livekit.agents.console
       ```

    ## Configuration

    Edit `#{agent_name}.ex` to customize your agent's behavior.
    """

    File.write!(Path.join(agent_dir, "README.md"), readme_content)
  end

  defp create_voice_template(agent_dir, agent_name) do
    # Create voice agent with more advanced features
    create_basic_template(agent_dir, agent_name)

    # Add voice-specific configuration
    voice_config_content = """
    # Voice Agent Configuration

    This is a voice-enabled agent template with STT, LLM, and TTS capabilities.

    ## Required Environment Variables

    ```
    # LiveKit
    export LIVEKIT_URL="ws://localhost:7880"
    export LIVEKIT_API_KEY="your-api-key"
    export LIVEKIT_API_SECRET="your-api-secret"

    # AI Providers
    export DEEPGRAM_API_KEY="your-deepgram-key"
    export OPENAI_API_KEY="your-openai-key"
    ```

    ## Features

    - Speech-to-text with Deepgram
    - Language model with OpenAI
    - Text-to-speech with OpenAI
    - Voice activity detection
    - Turn management
    """

    File.write!(Path.join(agent_dir, "VOICE_CONFIG.md"), voice_config_content)
  end

  defp create_advanced_template(agent_dir, agent_name) do
    create_voice_template(agent_dir, agent_name)

    # Add advanced features documentation
    advanced_content = """
    # Advanced Agent Features

    This template includes:

    - Multi-agent coordination
    - Custom tool integrations
    - Advanced conversation management
    - Metrics and monitoring
    - Error handling and recovery

    ## Architecture

    ```
    Agent Worker
    ├── Voice Agent
    │   ├── STT Provider
    │   ├── LLM Provider
    │   └── TTS Provider
    ├── Agent Session
    └── Job Context
    ```
    """

    File.write!(Path.join(agent_dir, "ADVANCED.md"), advanced_content)
  end

  defp show_help do
    Mix.shell().info(@moduledoc)
  end
end
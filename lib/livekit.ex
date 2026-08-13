defmodule Livekit do
  @moduledoc """
  Livekit server SDK for Elixir.

  This SDK enables you to manage Livekit rooms, access tokens, and voice agents programmatically.

  ## Core Features

  - **Room Management**: Create, manage, and monitor LiveKit rooms
  - **Access Tokens**: Generate JWT tokens for room access
  - **Voice Agents**: Build AI-powered voice assistants with STT, LLM, and TTS
  - **Audio Processing**: Handle audio frames and voice activity detection
  - **Agent Workers**: Deploy and manage agent lifecycles

  ## Voice Agents

  The voice agents framework provides a complete solution for building
  conversational AI applications:

      # Configure a voice agent
      config = %Livekit.Agents.VoiceAgent.Config{
        stt: {Livekit.Agents.STT.Deepgram, %{api_key: "your_key"}},
        llm: {Livekit.Agents.LLM.OpenAI, %{api_key: "your_key", model: "gpt-4o-mini"}},
        tts: {Livekit.Agents.TTS.OpenAI, %{api_key: "your_key", voice: "alloy"}},
        instructions: "You are a helpful assistant."
      }

      # Start the agent
      {:ok, agent} = Livekit.Agents.VoiceAgent.start_link(config)

  ## Development Tools

  Use Mix tasks for agent development:

      # Start an agent in console mode for testing
      mix livekit.agents.console

      # Create a new agent template
      mix livekit.agents.create my_agent --template voice

  See `Livekit.Agents.VoiceAgent`, `Livekit.Agents.Worker`, and
  `Livekit.Agents.AgentSession` for more information.
  """

  @version "0.1.4"

  @doc """
  Returns the current version of the Livekit SDK.
  """
  def version, do: @version

  @doc """
  Hello world.

  ## Examples

      iex> Livekit.hello()
      :world

  """
  def hello do
    :world
  end
end

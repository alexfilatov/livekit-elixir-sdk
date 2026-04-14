defmodule Livekit.Agents.LLMTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.LLM.LLMChunk

  defmodule StubLLM do
    use Livekit.Agents.LLM

    @impl true
    def chat(_chat_context, _opts) do
      {:ok, %{role: :assistant, content: "Hello!"}}
    end

    @impl true
    def capabilities do
      %{streaming: false, tool_calling: false, vision: false, max_context_tokens: 4096}
    end
  end

  test "StubLLM.chat/2 returns {:ok, chat_message map}" do
    assert {:ok, msg} = StubLLM.chat([], [])
    assert msg.role == :assistant
    assert msg.content == "Hello!"
  end

  test "chat/2 accepts term() as chat_context" do
    assert {:ok, _} = StubLLM.chat("any term", [])
    assert {:ok, _} = StubLLM.chat(%{messages: []}, [])
    assert {:ok, _} = StubLLM.chat(nil, [])
  end

  test "capabilities/0 returns map with all required LLM keys" do
    caps = StubLLM.capabilities()
    assert Map.has_key?(caps, :streaming)
    assert Map.has_key?(caps, :tool_calling)
    assert Map.has_key?(caps, :vision)
    assert Map.has_key?(caps, :max_context_tokens)
  end

  test "capabilities max_context_tokens is a positive integer or nil" do
    caps = StubLLM.capabilities()
    assert is_integer(caps.max_context_tokens) or is_nil(caps.max_context_tokens)
  end

  test "default validate_config/1 returns :ok" do
    assert :ok == StubLLM.validate_config(%{})
  end

  test "LLMChunk struct has correct defaults" do
    chunk = %LLMChunk{}
    assert chunk.type == nil
    assert chunk.content == nil
  end

  test "LLMChunk struct accepts all valid type atoms" do
    assert %LLMChunk{type: :text, content: "hi"}
    assert %LLMChunk{type: :tool_call, content: %{}}
    assert %LLMChunk{type: :done}
  end
end

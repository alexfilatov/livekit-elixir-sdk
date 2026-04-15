defmodule Livekit.Agents.LLM.FallbackTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.ChatContext
  alias Livekit.Agents.LLM.Fallback
  alias Livekit.Agents.LLM.Fallback.Config
  alias Livekit.Agents.LLM.LLMChunk

  # ---------------------------------------------------------------------------
  # Minimal mock LLM providers
  # ---------------------------------------------------------------------------

  defmodule OkProvider do
    use Livekit.Agents.LLM

    @impl true
    def chat(_ctx, opts) do
      config = Keyword.get(opts, :config, %{})
      content = Map.get(config, :content, "ok response")
      {:ok, %{role: :assistant, content: content}}
    end

    @impl true
    def capabilities do
      %{streaming: false, tool_calling: false, vision: false, max_context_tokens: 4096}
    end
  end

  defmodule ErrorProvider do
    use Livekit.Agents.LLM

    @impl true
    def chat(_ctx, _opts), do: {:error, :api_down}

    @impl true
    def capabilities do
      %{streaming: false, tool_calling: false, vision: false, max_context_tokens: 4096}
    end
  end

  defmodule StreamingProvider do
    use Livekit.Agents.LLM

    @impl true
    def chat(_ctx, _opts), do: {:ok, %{role: :assistant, content: "streamed"}}

    @impl true
    def stream(_ctx, _opts) do
      subscriber = self()

      pid =
        spawn(fn ->
          send(subscriber, {:llm_chunk, %LLMChunk{type: :text, content: "streamed"}})
          send(subscriber, {:llm_chunk, %LLMChunk{type: :done}})
        end)

      {:ok, pid}
    end

    @impl true
    def capabilities do
      %{streaming: true, tool_calling: false, vision: false, max_context_tokens: 4096}
    end
  end

  defmodule FailingStreamProvider do
    use Livekit.Agents.LLM

    @impl true
    def chat(_ctx, _opts), do: {:ok, %{role: :assistant, content: "batch"}}

    @impl true
    def stream(_ctx, _opts), do: {:error, :stream_unavailable}

    @impl true
    def capabilities do
      %{streaming: true, tool_calling: false, vision: false, max_context_tokens: 4096}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp empty_ctx do
    ChatContext.new()
  end

  # ---------------------------------------------------------------------------
  # capabilities/0
  # ---------------------------------------------------------------------------

  describe "capabilities/0" do
    test "returns a valid capability map" do
      caps = Fallback.capabilities()
      assert is_boolean(caps.streaming)
      assert is_boolean(caps.tool_calling)
      assert is_boolean(caps.vision)
    end
  end

  # ---------------------------------------------------------------------------
  # validate_config/1
  # ---------------------------------------------------------------------------

  describe "validate_config/1" do
    test "returns error when primary is nil" do
      config = %Config{primary: nil, secondary: {OkProvider, %{}}}
      assert {:error, :missing_primary} = Fallback.validate_config(config)
    end

    test "returns error when secondary is nil" do
      config = %Config{primary: {OkProvider, %{}}, secondary: nil}
      assert {:error, :missing_secondary} = Fallback.validate_config(config)
    end

    test "returns :ok with valid primary and secondary" do
      config = %Config{primary: {OkProvider, %{}}, secondary: {OkProvider, %{}}}
      assert :ok = Fallback.validate_config(config)
    end
  end

  # ---------------------------------------------------------------------------
  # chat/2 — primary succeeds
  # ---------------------------------------------------------------------------

  describe "chat/2 when primary succeeds" do
    test "returns primary result without calling secondary" do
      config = %Config{
        primary: {OkProvider, %{content: "from primary"}},
        secondary: {OkProvider, %{content: "from secondary"}}
      }

      assert {:ok, message} = Fallback.chat(empty_ctx(), config: config)
      assert message.content == "from primary"
    end

    test "returns message with :assistant role" do
      config = %Config{
        primary: {OkProvider, %{}},
        secondary: {ErrorProvider, %{}}
      }

      assert {:ok, message} = Fallback.chat(empty_ctx(), config: config)
      assert message.role == :assistant
    end
  end

  # ---------------------------------------------------------------------------
  # chat/2 — primary fails, secondary used
  # ---------------------------------------------------------------------------

  describe "chat/2 when primary fails" do
    test "falls back to secondary on primary error" do
      config = %Config{
        primary: {ErrorProvider, %{}},
        secondary: {OkProvider, %{content: "secondary response"}}
      }

      assert {:ok, message} = Fallback.chat(empty_ctx(), config: config)
      assert message.content == "secondary response"
    end

    test "returns error when both primary and secondary fail" do
      config = %Config{
        primary: {ErrorProvider, %{}},
        secondary: {ErrorProvider, %{}}
      }

      assert {:error, :api_down} = Fallback.chat(empty_ctx(), config: config)
    end
  end

  # ---------------------------------------------------------------------------
  # stream/2 — primary stream succeeds
  # ---------------------------------------------------------------------------

  describe "stream/2 when primary supports streaming" do
    test "delegates stream to primary provider" do
      config = %Config{
        primary: {StreamingProvider, %{}},
        secondary: {OkProvider, %{}}
      }

      assert {:ok, _pid} = Fallback.stream(empty_ctx(), config: config)

      assert_receive {:llm_chunk, %LLMChunk{type: :text, content: "streamed"}}, 500
      assert_receive {:llm_chunk, %LLMChunk{type: :done}}, 500
    end
  end

  # ---------------------------------------------------------------------------
  # stream/2 — primary stream fails, secondary used
  # ---------------------------------------------------------------------------

  describe "stream/2 when primary stream fails" do
    test "falls back to secondary stream when primary stream errors" do
      config = %Config{
        primary: {FailingStreamProvider, %{}},
        secondary: {StreamingProvider, %{}}
      }

      assert {:ok, _pid} = Fallback.stream(empty_ctx(), config: config)

      assert_receive {:llm_chunk, %LLMChunk{type: :text}}, 500
      assert_receive {:llm_chunk, %LLMChunk{type: :done}}, 500
    end

    test "returns error when secondary also lacks streaming" do
      config = %Config{
        primary: {ErrorProvider, %{}},
        secondary: {ErrorProvider, %{}}
      }

      assert {:error, :no_provider_supports_streaming} =
               Fallback.stream(empty_ctx(), config: config)
    end

    test "returns error when primary fails streaming and secondary has no stream/2" do
      config = %Config{
        primary: {FailingStreamProvider, %{}},
        secondary: {OkProvider, %{}}
      }

      assert {:error, :secondary_does_not_support_streaming} =
               Fallback.stream(empty_ctx(), config: config)
    end
  end
end

defmodule Livekit.Agents.Pipeline.GreetingTest do
  use ExUnit.Case, async: true

  @moduledoc """
  The agent speaking first.

  For an agent somebody was sent to — a QR code on an estate agent's board —
  silence on arrival is indistinguishable from a broken page. They have just
  granted microphone permission and have no idea whether to start talking.
  """

  alias Livekit.Agents.{AudioFrame, ChatContext, Pipeline}

  defmodule EchoTTS do
    @behaviour Livekit.Agents.TTS

    @impl true
    def synthesize(text, _opts), do: {:ok, "AUDIO:" <> text}
    @impl true
    def stream(_config), do: {:error, :not_implemented}
    @impl true
    def capabilities, do: %{streaming: false, voices: ["demo"], formats: [:pcm16]}
    @impl true
    def validate_config(_config), do: :ok
  end

  defmodule DeadTTS do
    @behaviour Livekit.Agents.TTS

    @impl true
    def synthesize(_text, _opts), do: {:error, :provider_down}
    @impl true
    def stream(_config), do: {:error, :not_implemented}
    @impl true
    def capabilities, do: %{streaming: false, voices: [], formats: [:pcm16]}
    @impl true
    def validate_config(_config), do: :ok
  end

  defmodule NoopSTT do
    @behaviour Livekit.Agents.STT

    @impl true
    def transcribe(_audio, _opts),
      do: {:ok, %Livekit.Agents.STT.SpeechEvent{type: :final, text: "", confidence: 1.0}}

    @impl true
    def stream(_config), do: {:error, :not_implemented}
    @impl true
    def capabilities, do: %{streaming: false, interim_results: false, languages: ["en"]}
    @impl true
    def validate_config(_config), do: :ok
  end

  defmodule NoopLLM do
    @behaviour Livekit.Agents.LLM

    @impl true
    def chat(_ctx, _opts), do: {:ok, %{role: :assistant, content: "ok"}}
    @impl true
    def stream(_ctx, _opts), do: {:error, :not_implemented}
    @impl true
    def capabilities,
      do: %{streaming: false, tool_calling: false, vision: false, max_context_tokens: 4096}

    @impl true
    def validate_config(_config), do: :ok
  end

  defp start(opts) do
    config =
      struct!(
        Pipeline.Config,
        [stt: {NoopSTT, %{}}, llm: {NoopLLM, %{}}, subscriber: self()] ++ opts
      )

    {:ok, pid} = Pipeline.start_link(config)
    on_exit(fn -> if Process.alive?(pid), do: Pipeline.stop(pid) end)
    pid
  end

  test "speaks the greeting without anybody saying anything first" do
    start(tts: {EchoTTS, %{}}, greeting: "This is 14 Elm Road, on for £400,000.")

    assert_receive {:pipeline_audio, %AudioFrame{data: data}}, 2000
    assert data == "AUDIO:This is 14 Elm Road, on for £400,000."
  end

  test "the greeting is in the chat context, so it is not said twice" do
    pid = start(tts: {EchoTTS, %{}}, greeting: "This is 14 Elm Road.")
    assert_receive {:pipeline_audio, _}, 2000

    messages = pid |> Pipeline.get_chat_context() |> ChatContext.messages()

    # Without this the model's first real turn introduces the property again,
    # having no idea it already has.
    assert [%{role: :assistant} = msg] = messages
    assert to_string(msg.content) =~ "14 Elm Road"
  end

  test "with no subscriber yet, the greeting waits for one" do
    config =
      struct!(Pipeline.Config,
        stt: {NoopSTT, %{}},
        llm: {NoopLLM, %{}},
        tts: {EchoTTS, %{}},
        greeting: "This is 14 Elm Road.",
        subscriber: nil
      )

    {:ok, pid} = Pipeline.start_link(config)
    on_exit(fn -> if Process.alive?(pid), do: Pipeline.stop(pid) end)

    # Nobody is listening yet. Greeting now would synthesise the opening line
    # and hand it to nothing — which is exactly what happened when RoomIO
    # claimed the output a moment after the pipeline started.
    refute_receive {:pipeline_audio, _}, 300

    # Claiming the output is not enough: an agent is dispatched when the room
    # is created, before the visitor has finished joining, and audio published
    # into an empty room is discarded rather than buffered.
    Pipeline.set_subscriber(pid, self())
    refute_receive {:pipeline_audio, _}, 300

    Pipeline.greet(pid)
    assert_receive {:pipeline_audio, %AudioFrame{data: "AUDIO:This is 14 Elm Road."}}, 2000
  end

  test "greeting twice is still one greeting" do
    config =
      struct!(Pipeline.Config,
        stt: {NoopSTT, %{}},
        llm: {NoopLLM, %{}},
        tts: {EchoTTS, %{}},
        greeting: "This is 14 Elm Road.",
        subscriber: nil
      )

    {:ok, pid} = Pipeline.start_link(config)
    on_exit(fn -> if Process.alive?(pid), do: Pipeline.stop(pid) end)

    Pipeline.set_subscriber(pid, self())
    Pipeline.greet(pid)
    assert_receive {:pipeline_audio, _}, 2000

    # A visitor who reconnects a track must not be introduced to twice.
    Pipeline.greet(pid)
    refute_receive {:pipeline_audio, _}, 300
  end

  test "claiming the output twice does not greet twice" do
    pid = start(tts: {EchoTTS, %{}}, greeting: "This is 14 Elm Road.")
    assert_receive {:pipeline_audio, _}, 2000

    Pipeline.set_subscriber(pid, self())

    # A board that introduces itself twice sounds broken.
    refute_receive {:pipeline_audio, _}, 300
  end

  test "no greeting configured means the agent waits, as before" do
    start(tts: {EchoTTS, %{}})
    refute_receive {:pipeline_audio, _}, 300
  end

  test "a blank greeting is not a greeting" do
    start(tts: {EchoTTS, %{}}, greeting: "   ")
    refute_receive {:pipeline_audio, _}, 300
  end

  test "a greeting that fails to synthesise does not kill the session" do
    pid = start(tts: {DeadTTS, %{}}, greeting: "Hello.")

    # The visitor can still speak first, which is strictly better than a room
    # that died on the way in.
    Process.sleep(200)
    assert Process.alive?(pid)
    refute_receive {:pipeline_audio, _}, 100
  end
end

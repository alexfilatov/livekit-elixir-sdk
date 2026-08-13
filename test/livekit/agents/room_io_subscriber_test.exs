defmodule Livekit.Agents.RoomIOSubscriberTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Who receives the agent's synthesised speech.

  `AgentSession` starts the pipeline before RoomIO exists, so it can only name
  itself as subscriber — and it has no handler for `{:pipeline_audio, _}`.
  Every frame the agent produced was therefore discarded: it joined the room,
  published no track, and said nothing. From the visitor's side that is
  indistinguishable from an agent that never arrived.
  """

  alias Livekit.Agents.{AudioFrame, Pipeline, RoomIO}

  defmodule StubSTT do
    @behaviour Livekit.Agents.STT
    @impl true
    def transcribe(_a, _o),
      do: {:ok, %Livekit.Agents.STT.SpeechEvent{type: :final, text: "", confidence: 1.0}}

    @impl true
    def stream(_c), do: {:error, :not_implemented}
    @impl true
    def capabilities, do: %{streaming: false, interim_results: false, languages: ["en"]}
    @impl true
    def validate_config(_c), do: :ok
  end

  defmodule StubLLM do
    @behaviour Livekit.Agents.LLM
    @impl true
    def chat(_ctx, _o), do: {:ok, %{role: :assistant, content: "hi"}}
    @impl true
    def stream(_c, _o), do: {:error, :not_implemented}
    @impl true
    def capabilities,
      do: %{streaming: false, tool_calling: false, vision: false, max_context_tokens: 4096}

    @impl true
    def validate_config(_c), do: :ok
  end

  defmodule StubTTS do
    @behaviour Livekit.Agents.TTS
    @impl true
    def synthesize(text, _o), do: {:ok, "AUDIO:" <> text}
    @impl true
    def stream(_c), do: {:error, :not_implemented}
    @impl true
    def capabilities, do: %{streaming: false, voices: [], formats: [:pcm16]}
    @impl true
    def validate_config(_c), do: :ok
  end

  # Stands in for the Room: records what RoomIO tries to publish.
  defmodule RecordingRoom do
    use GenServer
    def start_link(reporter), do: GenServer.start_link(__MODULE__, reporter)
    @impl true
    def init(reporter), do: {:ok, reporter}
    @impl true
    def handle_call({:subscribe_events, _pid}, _from, s), do: {:reply, :ok, s}
    @impl true
    def handle_call(:room_ref, _from, s), do: {:reply, make_ref(), s}
    @impl true
    def handle_call(:nif_module, _from, s), do: {:reply, __MODULE__, s}
    # The NIF surface RoomIO reaches through AudioTrack.publish/2.
    def audio_publish_frame(_ref, data, _rate, _ch) do
      send(Application.fetch_env!(:livekit, :test_reporter), {:published, data})
      :ok
    end
  end

  setup do
    Application.put_env(:livekit, :test_reporter, self())
    on_exit(fn -> Application.delete_env(:livekit, :test_reporter) end)
    :ok
  end

  test "RoomIO takes over the pipeline's audio output" do
    {:ok, room} = RecordingRoom.start_link(self())

    {:ok, pipeline} =
      Pipeline.start_link(%Pipeline.Config{
        stt: {StubSTT, %{}},
        llm: {StubLLM, %{}},
        tts: {StubTTS, %{}},
        # Whatever started the pipeline named itself, as AgentSession does.
        subscriber: self()
      })

    {:ok, _room_io} = RoomIO.start_link(%RoomIO.Config{room_pid: room, pipeline_pid: pipeline})

    # After RoomIO exists, the pipeline must send audio to IT, not to
    # whoever happened to start it.
    assert :sys.get_state(pipeline).config.subscriber != self()

    on_exit(fn -> if Process.alive?(pipeline), do: Pipeline.stop(pipeline) end)
  end

  test "a greeting reaches the room rather than being dropped" do
    {:ok, room} = RecordingRoom.start_link(self())

    {:ok, pipeline} =
      Pipeline.start_link(%Pipeline.Config{
        stt: {StubSTT, %{}},
        llm: {StubLLM, %{}},
        tts: {StubTTS, %{}},
        subscriber: self()
      })

    {:ok, room_io} = RoomIO.start_link(%RoomIO.Config{room_pid: room, pipeline_pid: pipeline})

    send(room_io, {:pipeline_audio, %AudioFrame{data: "AUDIO:hello", sample_rate: 48_000}})

    assert_receive {:published, "AUDIO:hello"}, 2000
    on_exit(fn -> if Process.alive?(pipeline), do: Pipeline.stop(pipeline) end)
  end
end

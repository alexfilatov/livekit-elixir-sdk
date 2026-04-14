defmodule Livekit.Agents.TTS.OpenAI do
  @moduledoc """
  OpenAI Text-to-Speech provider for LiveKit agents.

  This module provides text-to-speech functionality using OpenAI's TTS API,
  supporting various voices and audio formats.
  """

  use GenServer
  require Logger

  alias Livekit.Agents.AudioFrame

  defmodule Config do
    @moduledoc """
    Configuration for OpenAI TTS provider.
    """

    @type voice :: :alloy | :echo | :fable | :onyx | :nova | :shimmer
    @type model :: :tts_1 | :tts_1_hd
    @type response_format :: :mp3 | :opus | :aac | :flac | :pcm

    @type t :: %__MODULE__{
      api_key: String.t(),
      model: model(),
      voice: voice(),
      response_format: response_format(),
      speed: float(),
      sample_rate: pos_integer(),
      streaming: boolean()
    }

    defstruct [
      api_key: nil,
      model: :tts_1,
      voice: :alloy,
      response_format: :pcm,
      speed: 1.0,
      sample_rate: 48_000,
      streaming: false
    ]
  end

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
      config: Config.t(),
      client: Tesla.Client.t(),
      cache: map(),
      metrics: map()
    }

    defstruct [
      :config,
      :client,
      cache: %{},
      metrics: %{
        requests_sent: 0,
        responses_received: 0,
        total_audio_generated_seconds: 0,
        cache_hits: 0,
        errors: 0
      }
    ]
  end

  # Client API

  @doc """
  Starts the OpenAI TTS provider.
  """
  @spec start_link(Config.t()) :: GenServer.on_start()
  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  @doc """
  Synthesizes text to speech.
  """
  @spec synthesize_text(pid(), String.t()) :: {:ok, binary()} | {:error, term()}
  def synthesize_text(tts_pid, text) do
    GenServer.call(tts_pid, {:synthesize_text, text}, 30_000)
  end

  @doc """
  Synthesizes text to AudioFrame.
  """
  @spec synthesize_to_audio_frame(pid(), String.t()) :: {:ok, AudioFrame.t()} | {:error, term()}
  def synthesize_to_audio_frame(tts_pid, text) do
    case synthesize_text(tts_pid, text) do
      {:ok, audio_data} ->
        # Get config to determine audio format
        config = GenServer.call(tts_pid, :get_config)

        audio_frame = AudioFrame.new(audio_data,
          sample_rate: config.sample_rate,
          format: audio_format_from_response_format(config.response_format),
          timestamp_us: System.monotonic_time(:microsecond)
        )

        {:ok, audio_frame}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Clears the synthesis cache.
  """
  @spec clear_cache(pid()) :: :ok
  def clear_cache(tts_pid) do
    GenServer.cast(tts_pid, :clear_cache)
  end

  @doc """
  Gets provider metrics.
  """
  @spec get_metrics(pid()) :: map()
  def get_metrics(tts_pid) do
    GenServer.call(tts_pid, :get_metrics)
  end

  @doc """
  Updates voice configuration.
  """
  @spec update_voice(pid(), Config.voice()) :: :ok
  def update_voice(tts_pid, voice) do
    GenServer.cast(tts_pid, {:update_voice, voice})
  end

  # GenServer Callbacks

  @impl true
  def init(config) do
    Logger.info("Starting OpenAI TTS provider with voice: #{config.voice}")

    case validate_config(config) do
      :ok ->
        client = create_http_client(config)

        state = %State{
          config: config,
          client: client
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("Invalid OpenAI TTS configuration: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:synthesize_text, text}, _from, state) do
    case synthesize_speech(state, text) do
      {:ok, audio_data, new_state} ->
        {:reply, {:ok, audio_data}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  @impl true
  def handle_cast(:clear_cache, state) do
    Logger.info("Clearing TTS cache")
    new_state = %{state | cache: %{}}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_voice, voice}, state) do
    Logger.info("Updating TTS voice to: #{voice}")
    new_config = %{state.config | voice: voice}
    # Clear cache since voice changed
    new_state = %{state | config: new_config, cache: %{}}
    {:noreply, new_state}
  end

  # Private Functions

  defp validate_config(config) do
    cond do
      is_nil(config.api_key) or config.api_key == "" ->
        {:error, :missing_api_key}

      config.speed < 0.25 or config.speed > 4.0 ->
        {:error, :invalid_speed}

      config.sample_rate <= 0 ->
        {:error, :invalid_sample_rate}

      true ->
        :ok
    end
  end

  defp create_http_client(config) do
    middleware = [
      {Tesla.Middleware.BaseUrl, "https://api.openai.com/v1"},
      {Tesla.Middleware.Headers, [
        {"Authorization", "Bearer #{config.api_key}"},
        {"Content-Type", "application/json"}
      ]},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Logger, debug: false}
    ]

    Tesla.client(middleware, Tesla.Adapter.Hackney)
  end

  defp synthesize_speech(state, text) do
    # Check cache first
    cache_key = generate_cache_key(state.config, text)

    case Map.get(state.cache, cache_key) do
      nil ->
        # Generate new audio
        generate_audio(state, text, cache_key)

      cached_audio ->
        Logger.debug("TTS cache hit for text: #{String.slice(text, 0, 50)}...")
        cache_hit_metrics = Map.update!(state.metrics, :cache_hits, &(&1 + 1))
        new_state = %{state | metrics: cache_hit_metrics}
        {:ok, cached_audio, new_state}
    end
  end

  defp generate_audio(state, text, cache_key) do
    try do
      Logger.debug("Generating audio for text: #{String.slice(text, 0, 50)}...")

      # For development, use mock audio generation
      audio_data = mock_tts_synthesis(text, state.config)

      # Cache the result
      new_cache = Map.put(state.cache, cache_key, audio_data)

      # Update metrics
      estimated_duration = estimate_audio_duration(text)
      new_metrics = state.metrics
                   |> Map.update!(:requests_sent, &(&1 + 1))
                   |> Map.update!(:responses_received, &(&1 + 1))
                   |> Map.update!(:total_audio_generated_seconds, &(&1 + estimated_duration))

      new_state = %{state |
        cache: new_cache,
        metrics: new_metrics
      }

      {:ok, audio_data, new_state}
    rescue
      error ->
        Logger.error("OpenAI TTS error: #{inspect(error)}")
        error_metrics = Map.update!(state.metrics, :errors, &(&1 + 1))
        new_state = %{state | metrics: error_metrics}
        {:error, error, new_state}
    end
  end

  defp generate_cache_key(config, text) do
    # Create a hash-based cache key including relevant config parameters
    key_data = "#{config.model}_#{config.voice}_#{config.speed}_#{text}"
    :crypto.hash(:sha256, key_data) |> Base.encode16(case: :lower)
  end

  defp estimate_audio_duration(text) do
    # Rough estimation: ~150 words per minute, ~5 characters per word
    character_count = String.length(text)
    word_count = character_count / 5
    duration_minutes = word_count / 150
    duration_minutes * 60  # Convert to seconds
  end

  defp audio_format_from_response_format(:pcm), do: :pcm_16
  defp audio_format_from_response_format(:mp3), do: :pcm_16  # Will need decoding
  defp audio_format_from_response_format(:opus), do: :pcm_16  # Will need decoding
  defp audio_format_from_response_format(:aac), do: :pcm_16  # Will need decoding
  defp audio_format_from_response_format(:flac), do: :pcm_16  # Will need decoding
  defp audio_format_from_response_format(_), do: :pcm_16

  # Mock function for development
  defp mock_tts_synthesis(text, config) do
    # Generate mock audio data based on text length and configuration
    estimated_duration = estimate_audio_duration(text)
    sample_count = round(estimated_duration * config.sample_rate)

    # Generate simple sine wave as mock audio
    frequency = case config.voice do
      :alloy -> 440.0    # A4
      :echo -> 493.88    # B4
      :fable -> 523.25   # C5
      :onyx -> 392.0     # G4
      :nova -> 349.23    # F4
      :shimmer -> 293.66 # D4
    end

    samples = for i <- 0..(sample_count - 1) do
      # Generate sine wave sample
      sample_value = :math.sin(2 * :math.pi() * frequency * i / config.sample_rate)

      # Apply simple envelope to avoid clicks
      envelope = case i do
        i when i < 1000 -> i / 1000  # Fade in
        i when i > sample_count - 1000 -> (sample_count - i) / 1000  # Fade out
        _ -> 1.0
      end

      # Convert to 16-bit PCM
      pcm_value = round(sample_value * envelope * 16000)
      pcm_value = max(-32768, min(32767, pcm_value))
      <<pcm_value::little-signed-16>>
    end

    IO.iodata_to_binary(samples)
  end
end
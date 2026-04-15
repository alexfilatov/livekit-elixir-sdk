defmodule Livekit.Agents.Pipeline.EnergyVAD do
  @moduledoc """
  Energy-based Voice Activity Detection (VAD) classifier.

  Determines whether an audio frame contains speech or silence by computing
  the root-mean-square (RMS) energy of the frame and comparing it to a
  configurable threshold. Frames with RMS below the threshold are classified
  as `:silence`; frames at or above the threshold are classified as `:speech`.

  This module is stateless — `classify/2` is a pure function with no side
  effects. State management (timer-based turn boundary detection) is handled
  by `Livekit.Agents.Pipeline.TurnDetector`.

  ## Usage

      config = EnergyVAD.new(%{threshold: 0.02})
      case EnergyVAD.classify(frame, config) do
        :speech  -> # frame contains speech
        :silence -> # frame is silent
      end
  """

  alias Livekit.Agents.AudioFrame

  # ---------------------------------------------------------------------------
  # Config struct
  # ---------------------------------------------------------------------------

  defmodule Config do
    @moduledoc """
    Configuration for `Livekit.Agents.Pipeline.EnergyVAD`.

    ## Fields

    - `:threshold` — RMS amplitude threshold below which a frame is classified
      as silence. Defaults to `0.01` (normalised scale 0.0–1.0).
    """

    @type t :: %__MODULE__{threshold: float()}
    defstruct threshold: 0.01
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new `Config` struct from a map of options.

  ## Options

  - `:threshold` — RMS threshold (float). Defaults to `0.01`.

  ## Examples

      iex> Livekit.Agents.Pipeline.EnergyVAD.new(%{})
      %Livekit.Agents.Pipeline.EnergyVAD.Config{threshold: 0.01}

      iex> Livekit.Agents.Pipeline.EnergyVAD.new(%{threshold: 0.05})
      %Livekit.Agents.Pipeline.EnergyVAD.Config{threshold: 0.05}
  """
  @spec new(map()) :: Config.t()
  def new(opts) when is_map(opts) do
    threshold = Map.get(opts, :threshold, 0.01)
    %Config{threshold: threshold}
  end

  @doc """
  Classifies an audio frame as `:speech` or `:silence`.

  Delegates to `AudioFrame.silence?/2` using `config.threshold`. Returns
  `:silence` when the frame energy falls below the threshold, `:speech`
  otherwise.

  ## Examples

      iex> config = Livekit.Agents.Pipeline.EnergyVAD.new(%{})
      iex> frame = Livekit.Agents.AudioFrame.new(<<0::16>>, format: :pcm_16)
      iex> Livekit.Agents.Pipeline.EnergyVAD.classify(frame, config)
      :silence
  """
  @spec classify(AudioFrame.t(), Config.t()) :: :speech | :silence
  def classify(%AudioFrame{} = frame, %Config{} = config) do
    if AudioFrame.silence?(frame, config.threshold) do
      :silence
    else
      :speech
    end
  end
end

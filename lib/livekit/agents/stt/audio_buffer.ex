defmodule Livekit.Agents.STT.AudioBuffer do
  @moduledoc """
  Accumulates audio binary data until a configurable minimum duration threshold is met.

  Used by the Deepgram provider to avoid sending very short audio clips that produce
  empty transcriptions.

  ## Usage

      buf = AudioBuffer.new(min_duration_ms: 500)
      buf = AudioBuffer.push(buf, frame.data, frame.sample_rate)

      case AudioBuffer.flush_if_ready(buf) do
        {:ready, audio, new_buf} -> # send `audio` to Deepgram
        {:buffering, new_buf}    -> # keep accumulating
      end
  """

  @type t :: %__MODULE__{
          data: binary(),
          duration_ms: float(),
          min_duration_ms: non_neg_integer()
        }

  defstruct data: <<>>, duration_ms: 0.0, min_duration_ms: 100

  @doc """
  Creates a new empty buffer.

  ## Options

  - `:min_duration_ms` — minimum audio duration in milliseconds before `flush_if_ready/1`
    returns `{:ready, audio, buffer}` (default: `100`)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{min_duration_ms: Keyword.get(opts, :min_duration_ms, 100)}
  end

  @doc """
  Pushes raw audio bytes into the buffer. `sample_rate` is used to compute
  added duration (assumes 16-bit mono PCM — 2 bytes per sample).
  """
  @spec push(t(), binary(), pos_integer()) :: t()
  def push(%__MODULE__{} = buf, audio, sample_rate)
      when is_binary(audio) and sample_rate > 0 do
    added_ms = byte_size(audio) / 2 / sample_rate * 1000.0
    %{buf | data: buf.data <> audio, duration_ms: buf.duration_ms + added_ms}
  end

  @doc """
  Returns `{:ready, audio, reset_buffer}` if accumulated duration meets the
  threshold, otherwise `{:buffering, buffer}`.
  """
  @spec flush_if_ready(t()) :: {:ready, binary(), t()} | {:buffering, t()}
  def flush_if_ready(%__MODULE__{} = buf) do
    if buf.duration_ms >= buf.min_duration_ms do
      reset = %{buf | data: <<>>, duration_ms: 0.0}
      {:ready, buf.data, reset}
    else
      {:buffering, buf}
    end
  end

  @doc """
  Forces a flush regardless of accumulated duration. Useful on end-of-stream.
  Returns `{audio, reset_buffer}`. `audio` may be an empty binary if nothing
  was buffered.
  """
  @spec flush(t()) :: {binary(), t()}
  def flush(%__MODULE__{} = buf) do
    reset = %{buf | data: <<>>, duration_ms: 0.0}
    {buf.data, reset}
  end
end

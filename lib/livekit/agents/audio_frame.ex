defmodule Livekit.Agents.AudioFrame do
  @moduledoc """
  Represents an audio frame with metadata for voice processing.

  Audio frames are the basic unit of audio data flowing through the
  voice processing pipeline. They contain raw audio data along with
  metadata about the audio format and timing.
  """

  @type format :: :pcm_16 | :pcm_24 | :pcm_32 | :float32
  @type layout :: :mono | :stereo | :multi_channel

  @type t :: %__MODULE__{
          data: binary(),
          sample_rate: pos_integer(),
          channels: pos_integer(),
          format: format(),
          layout: layout(),
          samples_per_channel: pos_integer(),
          timestamp_us: non_neg_integer(),
          duration_us: non_neg_integer()
        }

  defstruct [
    :data,
    sample_rate: 48_000,
    channels: 1,
    format: :pcm_16,
    layout: :mono,
    samples_per_channel: 0,
    timestamp_us: 0,
    duration_us: 0
  ]

  @doc """
  Creates a new AudioFrame from raw audio data.

  ## Examples

      iex> audio_data = <<1, 2, 3, 4>>
      iex> frame = Livekit.Agents.AudioFrame.new(audio_data, sample_rate: 16000)
      iex> frame.sample_rate
      16000
  """
  @spec new(binary(), keyword()) :: t()
  def new(audio_data, opts \\ []) do
    sample_rate = Keyword.get(opts, :sample_rate, 48_000)
    channels = Keyword.get(opts, :channels, 1)
    format = Keyword.get(opts, :format, :pcm_16)
    layout = Keyword.get(opts, :layout, :mono)
    timestamp_us = Keyword.get(opts, :timestamp_us, 0)

    bytes_per_sample = bytes_per_sample_for_format(format)
    samples_per_channel = div(byte_size(audio_data), channels * bytes_per_sample)
    duration_us = calculate_duration_us(samples_per_channel, sample_rate)

    %__MODULE__{
      data: audio_data,
      sample_rate: sample_rate,
      channels: channels,
      format: format,
      layout: layout,
      samples_per_channel: samples_per_channel,
      timestamp_us: timestamp_us,
      duration_us: duration_us
    }
  end

  @doc """
  Creates an AudioFrame from WAV file data.
  """
  @spec from_wav(binary()) :: {:ok, t()} | {:error, term()}
  def from_wav(wav_data) do
    case parse_wav_header(wav_data) do
      {:ok, header, audio_data} ->
        frame =
          new(audio_data,
            sample_rate: header.sample_rate,
            channels: header.channels,
            format: wav_format_to_atom(header.format)
          )

        {:ok, frame}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Converts AudioFrame to raw PCM data.
  """
  @spec to_pcm(t()) :: binary()
  def to_pcm(%__MODULE__{data: data}), do: data

  @doc """
  Resamples audio frame to a different sample rate.
  """
  @spec resample(t(), pos_integer()) :: t()
  def resample(frame, new_sample_rate) when new_sample_rate == frame.sample_rate do
    frame
  end

  def resample(frame, new_sample_rate) do
    # Simple linear interpolation resampling
    # In production, this should use a proper resampling library
    ratio = new_sample_rate / frame.sample_rate

    case simple_resample(frame.data, frame.format, ratio) do
      {:ok, resampled_data} ->
        new(resampled_data,
          sample_rate: new_sample_rate,
          channels: frame.channels,
          format: frame.format,
          layout: frame.layout,
          timestamp_us: frame.timestamp_us
        )

      {:error, _} ->
        # If resampling fails, return original frame
        frame
    end
  end

  @doc """
  Converts audio frame to a different format.
  """
  @spec convert_format(t(), format()) :: t()
  def convert_format(frame, new_format) when new_format == frame.format do
    frame
  end

  def convert_format(frame, new_format) do
    case convert_audio_format(frame.data, frame.format, new_format) do
      {:ok, converted_data} ->
        %{frame | data: converted_data, format: new_format}

      {:error, _} ->
        # If conversion fails, return original frame
        frame
    end
  end

  @doc """
  Mixes multiple audio frames together.
  """
  @spec mix([t()]) :: {:ok, t()} | {:error, term()}
  def mix([]), do: {:error, :no_frames}
  def mix([frame]), do: {:ok, frame}

  def mix([frame1 | rest]) do
    # All frames should have compatible properties
    if frames_compatible?([frame1 | rest]) do
      mixed_data = mix_audio_data([frame1.data | Enum.map(rest, & &1.data)], frame1.format)
      mixed_frame = %{frame1 | data: mixed_data}
      {:ok, mixed_frame}
    else
      {:error, :incompatible_frames}
    end
  end

  @doc """
  Splits a stereo frame into separate mono frames.
  """
  @spec split_channels(t()) :: {:ok, [t()]} | {:error, term()}
  def split_channels(%__MODULE__{channels: 1} = frame) do
    {:ok, [frame]}
  end

  def split_channels(%__MODULE__{channels: 2} = frame) do
    case split_stereo_data(frame.data, frame.format) do
      {:ok, {left_data, right_data}} ->
        left_frame = %{frame | data: left_data, channels: 1, layout: :mono}
        right_frame = %{frame | data: right_data, channels: 1, layout: :mono}
        {:ok, [left_frame, right_frame]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def split_channels(_frame) do
    {:error, :unsupported_channel_count}
  end

  @doc """
  Gets the duration of the audio frame in milliseconds.
  """
  @spec duration_ms(t()) :: float()
  def duration_ms(frame) do
    frame.duration_us / 1000.0
  end

  @doc """
  Checks if the audio frame contains silence.
  """
  @spec is_silence?(t(), float()) :: boolean()
  def is_silence?(frame, threshold \\ 0.01) do
    rms = calculate_rms(frame.data, frame.format)
    rms < threshold
  end

  # Private Functions

  defp bytes_per_sample_for_format(:pcm_16), do: 2
  defp bytes_per_sample_for_format(:pcm_24), do: 3
  defp bytes_per_sample_for_format(:pcm_32), do: 4
  defp bytes_per_sample_for_format(:float32), do: 4

  defp calculate_duration_us(samples_per_channel, sample_rate) do
    round(samples_per_channel * 1_000_000 / sample_rate)
  end

  defp parse_wav_header(<<
         "RIFF",
         _file_size::little-32,
         "WAVE",
         "fmt ",
         format_chunk_size::little-32,
         format_tag::little-16,
         channels::little-16,
         sample_rate::little-32,
         _byte_rate::little-32,
         _block_align::little-16,
         bits_per_sample::little-16,
         rest::binary
       >>) do
    # Skip any extra format chunk data
    extra_size = format_chunk_size - 16

    case rest do
      <<_extra::binary-size(extra_size), "data", data_size::little-32,
        audio_data::binary-size(data_size), _::binary>> ->
        header = %{
          format: format_tag,
          channels: channels,
          sample_rate: sample_rate,
          bits_per_sample: bits_per_sample
        }

        {:ok, header, audio_data}

      _ ->
        {:error, :invalid_wav_format}
    end
  end

  defp parse_wav_header(_), do: {:error, :invalid_wav_header}

  # PCM
  defp wav_format_to_atom(1), do: :pcm_16
  # IEEE Float
  defp wav_format_to_atom(3), do: :float32
  # Default
  defp wav_format_to_atom(_), do: :pcm_16

  defp simple_resample(data, format, ratio) do
    # This is a very basic resampling implementation
    # In production, you'd want to use a proper library like libsamplerate
    try do
      sample_size = bytes_per_sample_for_format(format)
      sample_count = div(byte_size(data), sample_size)
      new_sample_count = round(sample_count * ratio)

      resampled =
        for i <- 0..(new_sample_count - 1) do
          source_index = round(i / ratio) * sample_size

          if source_index + sample_size <= byte_size(data) do
            binary_part(data, source_index, sample_size)
          else
            <<0::size(sample_size * 8)>>
          end
        end

      {:ok, IO.iodata_to_binary(resampled)}
    rescue
      _ -> {:error, :resample_failed}
    end
  end

  defp convert_audio_format(data, from_format, to_format) do
    # Basic format conversion - in production use a proper audio library
    try do
      converted =
        case {from_format, to_format} do
          {:pcm_16, :float32} -> pcm16_to_float32(data)
          {:float32, :pcm_16} -> float32_to_pcm16(data)
          # No conversion needed or unsupported
          _ -> data
        end

      {:ok, converted}
    rescue
      _ -> {:error, :conversion_failed}
    end
  end

  defp pcm16_to_float32(data) do
    for <<sample::little-signed-16 <- data>>, into: <<>> do
      float_sample = sample / 32768.0
      <<float_sample::little-float-32>>
    end
  end

  defp float32_to_pcm16(data) do
    for <<sample::little-float-32 <- data>>, into: <<>> do
      pcm_sample = round(sample * 32767.0)
      pcm_sample = max(-32768, min(32767, pcm_sample))
      <<pcm_sample::little-signed-16>>
    end
  end

  defp frames_compatible?(frames) do
    first = hd(frames)

    Enum.all?(frames, fn frame ->
      frame.sample_rate == first.sample_rate and
        frame.channels == first.channels and
        frame.format == first.format
    end)
  end

  defp mix_audio_data(data_list, :pcm_16) do
    # Simple additive mixing for PCM16
    max_length = Enum.max(Enum.map(data_list, &byte_size/1))

    # Pad all data to same length
    padded_data =
      Enum.map(data_list, fn data ->
        padding_size = max_length - byte_size(data)
        data <> <<0::size(padding_size * 8)>>
      end)

    # Mix samples
    for i <- 0..(div(max_length, 2) - 1), into: <<>> do
      mixed_sample =
        Enum.reduce(padded_data, 0, fn data, acc ->
          offset = i * 2
          <<_::binary-size(offset), sample::little-signed-16, _::binary>> = data
          acc + sample
        end)

      # Prevent clipping
      mixed_sample = max(-32768, min(32767, mixed_sample))
      <<mixed_sample::little-signed-16>>
    end
  end

  defp mix_audio_data(data_list, _format) do
    # For other formats, just return the first one for now
    hd(data_list)
  end

  defp split_stereo_data(data, :pcm_16) do
    try do
      {left_samples, right_samples} =
        for <<left::little-signed-16, right::little-signed-16 <- data>>, reduce: {[], []} do
          {left_acc, right_acc} -> {[left | left_acc], [right | right_acc]}
        end

      left_data =
        for sample <- Enum.reverse(left_samples), into: <<>>, do: <<sample::little-signed-16>>

      right_data =
        for sample <- Enum.reverse(right_samples), into: <<>>, do: <<sample::little-signed-16>>

      {:ok, {left_data, right_data}}
    rescue
      _ -> {:error, :split_failed}
    end
  end

  defp split_stereo_data(_data, _format) do
    {:error, :unsupported_format}
  end

  defp calculate_rms(data, :pcm_16) do
    samples = for <<sample::little-signed-16 <- data>>, do: sample

    if length(samples) == 0 do
      0.0
    else
      sum_of_squares =
        Enum.reduce(samples, 0, fn sample, acc ->
          normalized = sample / 32768.0
          acc + normalized * normalized
        end)

      :math.sqrt(sum_of_squares / length(samples))
    end
  end

  defp calculate_rms(_data, _format), do: 0.0
end

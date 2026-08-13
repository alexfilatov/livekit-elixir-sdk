defmodule Livekit.WebRTC.AudioTrack do
  @moduledoc """
  Audio track operations for LiveKit rooms (D-07).

  Subscribes to remote audio tracks (receiving `{:audio_frame, track_sid, binary}` messages)
  and publishes local audio frames to the room.
  """

  alias Livekit.Agents.AudioFrame
  alias Livekit.WebRTC.Room

  @doc """
  Subscribe to a remote audio track by its SID.

  Delivers `{:audio_frame, track_sid, binary}` messages to `subscriber_pid`.
  The binary is PCM int16 little-endian (compatible with `AudioFrame` format: `:pcm_16`).

  Returns `{:ok, track_resource_ref}` or `{:error, reason}`.
  """
  @spec subscribe(pid(), String.t(), pid()) :: {:ok, reference()} | {:error, term()}
  def subscribe(room_pid, track_sid, subscriber_pid) do
    room_ref = Room.room_ref(room_pid)
    nif = Room.nif_module(room_pid)

    case nif.audio_subscribe(room_ref, track_sid, subscriber_pid) do
      # `audio_subscribe` is `Result<ResourceArc<AudioTrackResource>, Error>`,
      # and rustler encodes `Ok` as the bare resource term — no `:ok` tuple.
      # Normalised here rather than at each caller: the same shape already bit
      # `room_connect`, and every caller downstream expects the tuple.
      track_ref when is_reference(track_ref) -> {:ok, track_ref}
      # Mock NIF modules in tests wrap it; keep accepting that.
      {:ok, track_ref} -> {:ok, track_ref}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Publish a local audio frame to the room.

  Accepts a `Livekit.Agents.AudioFrame` with `format: :pcm_16`.
  Returns `:ok` or `{:error, reason}`.
  """
  @spec publish(pid(), AudioFrame.t()) :: :ok | {:error, term()}
  def publish(room_pid, %AudioFrame{data: data, sample_rate: sr, channels: ch, format: :pcm_16}) do
    room_ref = Room.room_ref(room_pid)
    nif = Room.nif_module(room_pid)
    nif.audio_publish_frame(room_ref, data, sr, ch)
  end

  def publish(_room_pid, %AudioFrame{format: fmt}) do
    {:error, {:unsupported_format, fmt}}
  end

  @doc """
  Unsubscribe from an audio track by dropping the resource reference.

  The Rust `AbortHandle` in `AudioTrackResource` will be triggered when the
  `ResourceArc` is GC'd. Passing `nil` is a no-op.
  """
  @spec unsubscribe(reference() | nil) :: :ok
  def unsubscribe(nil), do: :ok

  def unsubscribe(_track_ref) do
    # ResourceArc GC handles cleanup via IMPLEMENTS_DOWN in Rust
    :ok
  end
end

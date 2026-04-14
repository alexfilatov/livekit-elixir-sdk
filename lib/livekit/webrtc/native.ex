defmodule Livekit.WebRTC.Native do
  @moduledoc """
  NIF bindings to the LiveKit WebRTC Rust client SDK.

  This module is loaded automatically via `@on_load` when the application
  starts. All functions raise `ErlangError` if the NIF is not loaded —
  this should never happen in normal operation.

  Do not call these functions directly from application code; use
  `Livekit.WebRTC.Room` and `Livekit.WebRTC.AudioTrack` instead.
  """

  use Rustler, otp_app: :livekit, crate: :livekit_webrtc

  # Room NIFs
  @doc "Connect to a LiveKit room. Returns an opaque room resource reference."
  @spec room_connect(String.t(), String.t(), pid()) :: {:ok, reference()} | {:error, String.t()}
  def room_connect(_url, _token, _listener_pid),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc "Disconnect from a LiveKit room and stop the event forwarding task."
  @spec room_disconnect(reference()) :: :ok
  def room_disconnect(_room_ref),
    do: :erlang.nif_error(:nif_not_loaded)

  # Audio NIFs
  @doc "Subscribe to a remote audio track. Starts streaming {:audio_frame, track_sid, binary} to subscriber_pid."
  @spec audio_subscribe(reference(), String.t(), pid()) ::
          {:ok, reference()} | {:error, String.t()}
  def audio_subscribe(_room_ref, _track_sid, _subscriber_pid),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc "Publish a PCM int16 audio frame to the room's local audio track."
  @spec audio_publish_frame(reference(), binary(), non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, String.t()}
  def audio_publish_frame(_room_ref, _audio_binary, _sample_rate, _channels),
    do: :erlang.nif_error(:nif_not_loaded)
end

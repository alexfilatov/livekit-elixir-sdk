defmodule Livekit.WebRTC.Native do
  @moduledoc """
  NIF bindings to the LiveKit WebRTC Rust client SDK.

  The NIF is compiled from `native/livekit_webrtc/` via Rustler.
  If the Rust toolchain is not available (e.g. CI), the module still
  compiles but all functions raise `:nif_not_loaded` at runtime.

  Set `LIVEKIT_SKIP_NATIVE=1` to skip NIF compilation.

  Do not call these functions directly from application code; use
  `Livekit.WebRTC.Room` and `Livekit.WebRTC.AudioTrack` instead.
  """

  # Whether to compile the Rust NIF at all.
  #
  # `:rustler` is an OPTIONAL dependency, so most consumers never fetch it —
  # they want tokens, the room service API or the agent plumbing, not a
  # WebRTC client. So this must degrade to stubs, not fail the build.
  @native? System.get_env("LIVEKIT_SKIP_NATIVE") != "1" and Code.ensure_loaded?(Rustler)

  # `use Rustler` cannot go in the untaken branch of a plain `if`. `if` is a
  # macro and Elixir expands BOTH branches, so `use Rustler` was expanded
  # even when it was not selected, and every consumer without rustler failed
  # with "module Rustler is not loaded" — LIVEKIT_SKIP_NATIVE=1 included,
  # which made the escape hatch useless.
  #
  # `quote` does not expand its contents, so the `use` is only ever expanded
  # by `Code.eval_quoted/3`, and only when the NIF is actually wanted.
  if @native? do
    Code.eval_quoted(
      quote do
        use Rustler, otp_app: :livekit, crate: :livekit_webrtc
      end,
      [],
      __ENV__
    )
  else
    @doc false
    def __init__, do: :ok
  end

  @doc "Whether this build has the Rust NIF. False means every function below raises."
  def native?, do: @native?

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

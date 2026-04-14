defmodule Livekit.WebRTC.VideoTrack do
  @moduledoc """
  Basic video track stub for LiveKit room video (D-08).

  Full video implementation is deferred to a future phase.
  This module exists so callers can pattern-match on the module name.
  """

  @doc "Subscribe to a remote video track. Currently not implemented."
  @spec subscribe(pid(), String.t(), pid()) :: {:error, :not_implemented}
  def subscribe(_room_pid, _track_sid, _subscriber_pid), do: {:error, :not_implemented}

  @doc "Unsubscribe from a remote video track. Currently not implemented."
  @spec unsubscribe(reference()) :: {:error, :not_implemented}
  def unsubscribe(_track_ref), do: {:error, :not_implemented}
end

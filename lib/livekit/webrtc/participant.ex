defmodule Livekit.WebRTC.Participant do
  @moduledoc """
  Represents a LiveKit room participant (D-09).

  Identity and metadata are extracted from room events and stored
  as simple string fields. Track listing is managed by the Room GenServer.
  """

  @type t :: %__MODULE__{
          identity: String.t(),
          metadata: String.t() | nil
        }

  defstruct [:identity, :metadata]

  @doc "Creates a new Participant struct."
  @spec new(String.t(), String.t() | nil) :: t()
  def new(identity, metadata \\ nil) do
    %__MODULE__{identity: identity, metadata: metadata}
  end

  @doc "Returns the participant's identity string."
  @spec identity(t()) :: String.t()
  def identity(%__MODULE__{identity: id}), do: id

  @doc "Returns the participant's metadata string, or nil if not set."
  @spec metadata(t()) :: String.t() | nil
  def metadata(%__MODULE__{metadata: m}), do: m
end

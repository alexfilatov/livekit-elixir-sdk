defmodule Livekit.Agents.Telephony.SIP do
  @moduledoc """
  SIP integration module for LiveKit telephony.

  Provides helpers for identifying and inspecting SIP participants in a LiveKit room.
  LiveKit's SIP integration attaches metadata to participant attributes (e.g. via the
  `livekit.sip.*` attribute namespace). This module decodes those attributes into a
  typed `SIPParticipant` struct.

  ## Usage

      case SIP.detect_sip_participant(participant_attributes) do
        {:ok, sip_participant} ->
          IO.inspect(sip_participant.phone_number)
        {:error, :not_a_sip_participant} ->
          :ok
      end
  """

  defmodule SIPParticipant do
    @moduledoc """
    Represents a SIP participant in a LiveKit room.

    ## Fields

    - `:phone_number` — The E.164 phone number of the caller/callee (e.g. `"+15551234567"`).
      May be `nil` if not provided by the SIP trunk.
    - `:call_id` — The SIP Call-ID header value identifying this call session.
    - `:direction` — `:inbound` (caller phoned in) or `:outbound` (agent called out).
    - `:trunk_id` — The LiveKit SIP trunk ID that handled this call. May be `nil`.
    - `:dialed_number` — The number that was dialed (DID/destination). May be `nil`.
    - `:metadata` — Raw attribute map from the participant, for accessing provider-specific fields.
    """

    @type direction :: :inbound | :outbound

    @type t :: %__MODULE__{
            phone_number: String.t() | nil,
            call_id: String.t() | nil,
            direction: direction() | nil,
            trunk_id: String.t() | nil,
            dialed_number: String.t() | nil,
            metadata: map()
          }

    defstruct [
      :phone_number,
      :call_id,
      :direction,
      :trunk_id,
      :dialed_number,
      metadata: %{}
    ]
  end

  @doc """
  Detects whether a participant is a SIP participant based on their attributes map.

  LiveKit's SIP bridge sets `"livekit.sip.callID"` (or `"sip.callID"`) on SIP participants.
  Returns `{:ok, SIPParticipant.t()}` if the participant is SIP, or
  `{:error, :not_a_sip_participant}` otherwise.

  ## Parameters

  - `attributes` — The participant's `attributes` map (string keys, string values).

  ## Examples

      iex> SIP.detect_sip_participant(%{
      ...>   "livekit.sip.callID" => "abc123",
      ...>   "livekit.sip.phoneNumber" => "+15551234567",
      ...>   "livekit.sip.callDirection" => "inbound"
      ...> })
      {:ok, %SIPParticipant{call_id: "abc123", phone_number: "+15551234567", direction: :inbound}}
  """
  @spec detect_sip_participant(map()) ::
          {:ok, SIPParticipant.t()} | {:error, :not_a_sip_participant}
  def detect_sip_participant(attributes) when is_map(attributes) do
    call_id =
      Map.get(attributes, "livekit.sip.callID") ||
        Map.get(attributes, "sip.callID") ||
        Map.get(attributes, "sip.call_id")

    if call_id do
      {:ok, build_sip_participant(call_id, attributes)}
    else
      {:error, :not_a_sip_participant}
    end
  end

  @doc """
  Extracts call metadata from a `SIPParticipant`.

  Returns a map with human-readable call information useful for logging or
  routing decisions.

  ## Keys

  - `"call_id"` — SIP Call-ID.
  - `"phone_number"` — Caller phone number (E.164) or `nil`.
  - `"dialed_number"` — Dialed/destination number or `nil`.
  - `"direction"` — `"inbound"` or `"outbound"` or `nil`.
  - `"trunk_id"` — SIP trunk ID or `nil`.

  ## Examples

      iex> sip = %SIPParticipant{call_id: "abc", phone_number: "+1555", direction: :inbound}
      iex> SIP.call_info(sip)
      %{"call_id" => "abc", "phone_number" => "+1555", "direction" => "inbound", ...}
  """
  @spec call_info(SIPParticipant.t()) :: map()
  def call_info(%SIPParticipant{} = participant) do
    %{
      "call_id" => participant.call_id,
      "phone_number" => participant.phone_number,
      "dialed_number" => participant.dialed_number,
      "direction" => direction_to_string(participant.direction),
      "trunk_id" => participant.trunk_id
    }
  end

  # Private Helpers

  @spec build_sip_participant(String.t(), map()) :: SIPParticipant.t()
  defp build_sip_participant(call_id, attributes) do
    phone_number =
      Map.get(attributes, "livekit.sip.phoneNumber") ||
        Map.get(attributes, "sip.phoneNumber") ||
        Map.get(attributes, "sip.phone_number")

    dialed_number =
      Map.get(attributes, "livekit.sip.dialedNumber") ||
        Map.get(attributes, "sip.dialedNumber") ||
        Map.get(attributes, "sip.dialed_number")

    trunk_id =
      Map.get(attributes, "livekit.sip.trunkID") ||
        Map.get(attributes, "sip.trunkID") ||
        Map.get(attributes, "sip.trunk_id")

    direction_raw =
      Map.get(attributes, "livekit.sip.callDirection") ||
        Map.get(attributes, "sip.callDirection") ||
        Map.get(attributes, "sip.direction")

    direction = parse_direction(direction_raw)

    %SIPParticipant{
      call_id: call_id,
      phone_number: phone_number,
      dialed_number: dialed_number,
      trunk_id: trunk_id,
      direction: direction,
      metadata: attributes
    }
  end

  @spec parse_direction(String.t() | nil) :: :inbound | :outbound | nil
  defp parse_direction("inbound"), do: :inbound
  defp parse_direction("outbound"), do: :outbound
  defp parse_direction(_), do: nil

  @spec direction_to_string(:inbound | :outbound | nil) :: String.t() | nil
  defp direction_to_string(:inbound), do: "inbound"
  defp direction_to_string(:outbound), do: "outbound"
  defp direction_to_string(nil), do: nil
end

defmodule Livekit.Agents.Telephony.WarmTransfer do
  @moduledoc """
  Call transfer helpers for telephony agents.

  Provides two transfer modes:

  - **Cold transfer** (`transfer/3`) — Immediately transfer the caller to a
    destination number or SIP URI. The current agent is removed from the call.

  - **Warm transfer** (`warm_transfer/4`) — Connect the caller to a new agent
    while the current agent stays on briefly to provide context (a "whisper").
    After the handoff, the original agent disconnects.

  ## LiveKit SIP Transfer

  In LiveKit, call transfers are performed via SIP `REFER` messages or by
  updating the participant's dispatch rule. This module emits transfer
  instructions as structured maps that the host agent or room controller
  should relay to the LiveKit server via the SIP API.

  ## Usage

      # Blind/cold transfer
      {:ok, instruction} = WarmTransfer.transfer(room_pid, sip_participant, "+15552223333")

      # Warm transfer with context whisper
      {:ok, instruction} = WarmTransfer.warm_transfer(
        room_pid,
        sip_participant,
        "+15552223333",
        context: "Caller wants to upgrade their subscription."
      )
  """

  alias Livekit.Agents.Telephony.SIP.SIPParticipant

  @doc """
  Initiates a cold (blind) transfer of a SIP call to the destination.

  Returns `{:ok, transfer_instruction}` where `transfer_instruction` is a map
  that the host application should send to the LiveKit SIP API to execute the
  REFER operation.

  ## Parameters

  - `room` — The room PID or name (used as context; actual API call is external).
  - `participant` — The `SIPParticipant` to transfer.
  - `destination` — Destination phone number (E.164) or SIP URI.

  ## Returns

  `{:ok, map()}` — Transfer instruction map with keys:
    - `"type"` — `"transfer"`
    - `"call_id"` — Source call ID.
    - `"destination"` — Target number/URI.
    - `"timestamp"` — ISO 8601 UTC timestamp.

  ## Examples

      iex> WarmTransfer.transfer(room, sip_participant, "+15559990000")
      {:ok, %{"type" => "transfer", "call_id" => "abc123", "destination" => "+15559990000"}}
  """
  @spec transfer(term(), SIPParticipant.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def transfer(_room, %SIPParticipant{} = participant, destination)
      when is_binary(destination) do
    with :ok <- validate_destination(destination) do
      instruction = %{
        "type" => "transfer",
        "call_id" => participant.call_id,
        "source_phone" => participant.phone_number,
        "destination" => destination,
        "transfer_mode" => "cold",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
      }

      {:ok, instruction}
    end
  end

  @doc """
  Initiates a warm transfer of a SIP call to the destination with a context handoff.

  A warm transfer first connects the current agent to the destination (the
  "whisper" phase), allows context to be communicated, and then bridges the
  caller in. This module returns instructions for both the whisper and handoff
  phases as a structured map.

  ## Parameters

  - `room` — The room PID or name (context; actual API call is external).
  - `participant` — The `SIPParticipant` to transfer.
  - `destination` — Destination phone number (E.164) or SIP URI.
  - `opts` — Keyword options:
    - `:context` — Text summary to whisper to the receiving agent. Default: `""`.
    - `:whisper_timeout_ms` — Milliseconds to wait in whisper before auto-bridging. Default: `30_000`.

  ## Returns

  `{:ok, map()}` — Warm transfer instruction map with keys:
    - `"type"` — `"warm_transfer"`
    - `"call_id"` — Source call ID.
    - `"destination"` — Target number/URI.
    - `"context"` — Context string for the receiving agent.
    - `"whisper_timeout_ms"` — Whisper timeout in milliseconds.
    - `"timestamp"` — ISO 8601 UTC timestamp.

  ## Examples

      iex> WarmTransfer.warm_transfer(room, sip_participant, "+15559990000",
      ...>   context: "Caller is asking about billing from account #42.")
      {:ok, %{"type" => "warm_transfer", "context" => "Caller is asking about billing...", ...}}
  """
  @spec warm_transfer(term(), SIPParticipant.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def warm_transfer(_room, %SIPParticipant{} = participant, destination, opts \\ [])
      when is_binary(destination) do
    context_text = Keyword.get(opts, :context, "")
    whisper_timeout_ms = Keyword.get(opts, :whisper_timeout_ms, 30_000)

    with :ok <- validate_destination(destination) do
      instruction = %{
        "type" => "warm_transfer",
        "call_id" => participant.call_id,
        "source_phone" => participant.phone_number,
        "destination" => destination,
        "transfer_mode" => "warm",
        "context" => context_text,
        "whisper_timeout_ms" => whisper_timeout_ms,
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
      }

      {:ok, instruction}
    end
  end

  # Private Helpers

  @spec validate_destination(String.t()) :: :ok | {:error, :invalid_destination}
  defp validate_destination(destination) do
    # Accept E.164 numbers or SIP URIs (sip:user@domain or sips:user@domain)
    valid_e164 = Regex.match?(~r/^\+\d{7,15}$/, destination)
    valid_sip = Regex.match?(~r/^sips?:[^@]+@.+$/, destination)

    if valid_e164 or valid_sip do
      :ok
    else
      {:error, :invalid_destination}
    end
  end
end

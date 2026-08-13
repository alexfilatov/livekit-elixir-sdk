defmodule Livekit.Agents.Telephony.DTMF do
  @moduledoc """
  DTMF (Dual-Tone Multi-Frequency) tone handling for telephony agents.

  Provides parsing of DTMF events from LiveKit data channel messages and a
  digit accumulation helper with timeout and terminator support.

  ## DTMF via LiveKit Data Channel

  LiveKit's SIP bridge forwards DTMF digits as data channel messages with a
  specific topic or payload format. This module decodes those messages into
  typed `DTMFEvent` structs.

  ## Usage

      case DTMF.parse_dtmf(data_channel_payload) do
        {:ok, event} -> IO.puts("Digit: \#{event.digit}")
        {:error, reason} -> Logger.warning("Invalid DTMF payload: \#{reason}")
      end

      # Accumulate digits until # is pressed or timeout
      {:ok, digits} = DTMF.collect_digits(digit_stream, terminator: "#", timeout_ms: 5_000)
  """

  defmodule DTMFEvent do
    @moduledoc """
    A single DTMF digit event received via the data channel.

    ## Fields

    - `:digit` — The DTMF digit character: `"0"`–`"9"`, `"*"`, or `"#"`.
    - `:timestamp` — UTC datetime when the digit was received.
    - `:duration_ms` — Duration the key was held, in milliseconds. May be `nil`.
    """

    @type digit :: String.t()

    @type t :: %__MODULE__{
            digit: digit(),
            timestamp: DateTime.t(),
            duration_ms: non_neg_integer() | nil
          }

    defstruct [:digit, :timestamp, :duration_ms]
  end

  @valid_digits ~w(0 1 2 3 4 5 6 7 8 9 * #)

  @doc """
  Parses a DTMF event from a LiveKit data channel message payload.

  Accepts either:
  - A JSON-encoded binary with `"digit"` key (and optional `"duration_ms"`)
  - A map already decoded from JSON

  Returns `{:ok, DTMFEvent.t()}` on success, or `{:error, reason}` if the
  payload is not a valid DTMF message.

  ## Examples

      iex> DTMF.parse_dtmf(~s({"digit":"5","duration_ms":100}))
      {:ok, %DTMFEvent{digit: "5", duration_ms: 100}}

      iex> DTMF.parse_dtmf(%{"digit" => "3"})
      {:ok, %DTMFEvent{digit: "3", duration_ms: nil}}

      iex> DTMF.parse_dtmf(~s({"digit":"Q"}))
      {:error, :invalid_digit}
  """
  @spec parse_dtmf(binary() | map()) :: {:ok, DTMFEvent.t()} | {:error, term()}
  def parse_dtmf(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, map} -> parse_dtmf(map)
      {:error, _} -> {:error, :invalid_json}
    end
  end

  def parse_dtmf(%{"digit" => digit} = map) when is_binary(digit) do
    if digit in @valid_digits do
      duration_ms = Map.get(map, "duration_ms")

      event = %DTMFEvent{
        digit: digit,
        timestamp: DateTime.utc_now(),
        duration_ms: duration_ms
      }

      {:ok, event}
    else
      {:error, :invalid_digit}
    end
  end

  def parse_dtmf(%{} = _map), do: {:error, :missing_digit}

  @doc """
  Accumulates DTMF digits from a list of `DTMFEvent` structs or digit strings.

  Stops accumulating when:
  - The terminator digit is encountered (default: `"#"`), or
  - The maximum digit count is reached (default: `20`).

  The terminator digit is NOT included in the returned digit string.

  ## Parameters

  - `events` — List of `DTMFEvent.t()` structs or digit strings (`"0"`–`"9"`, `"*"`, `"#"`).
  - `opts` — Keyword options:
    - `:terminator` — Digit string that signals end of input. Default: `"#"`.
    - `:max_digits` — Maximum digits to collect. Default: `20`.

  ## Returns

  - `{:ok, digits}` — Collected digit string (e.g. `"12345"`).
  - `{:error, :no_terminator}` — Input exhausted without hitting terminator.

  ## Examples

      iex> events = [%DTMFEvent{digit: "1"}, %DTMFEvent{digit: "2"}, %DTMFEvent{digit: "#"}]
      iex> DTMF.collect_digits(events)
      {:ok, "12"}

      iex> DTMF.collect_digits(["5", "5", "5", "1", "2", "3", "4"])
      {:error, :no_terminator}
  """
  @spec collect_digits([DTMFEvent.t() | String.t()], keyword()) ::
          {:ok, String.t()} | {:error, :no_terminator}
  def collect_digits(events, opts \\ []) when is_list(events) do
    terminator = Keyword.get(opts, :terminator, "#")
    max_digits = Keyword.get(opts, :max_digits, 20)

    digits =
      events
      |> Enum.map(&extract_digit/1)
      |> Enum.reject(&is_nil/1)

    do_collect(digits, terminator, max_digits, [])
  end

  # Private Helpers

  @spec extract_digit(DTMFEvent.t() | String.t()) :: String.t() | nil
  defp extract_digit(%DTMFEvent{digit: d}), do: d
  defp extract_digit(d) when is_binary(d) and d in @valid_digits, do: d
  defp extract_digit(_), do: nil

  @spec do_collect([String.t()], String.t(), non_neg_integer(), [String.t()]) ::
          {:ok, String.t()} | {:error, :no_terminator}
  defp do_collect([], _terminator, _max, _acc), do: {:error, :no_terminator}

  defp do_collect([term | _rest], term, _max, acc) do
    {:ok, IO.iodata_to_binary(Enum.reverse(acc))}
  end

  defp do_collect(_digits, _terminator, 0, acc) do
    {:ok, IO.iodata_to_binary(Enum.reverse(acc))}
  end

  defp do_collect([digit | rest], terminator, max, acc) do
    do_collect(rest, terminator, max - 1, [digit | acc])
  end
end

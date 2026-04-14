defmodule Livekit.Agents.Telephony.DataCollection do
  @moduledoc """
  Pre-built data collection workflows for common IVR use cases.

  Each function validates structured input (phone numbers, credit card numbers,
  dates, emails) and returns `{:ok, validated_value}` or `{:error, reason}` with
  a human-readable retry prompt suitable for TTS.

  ## Usage

      # Validate a collected phone number
      case DataCollection.collect_phone_number("+15551234567") do
        {:ok, normalized} -> IO.puts("Got number: \#{normalized}")
        {:error, {reason, retry_prompt}} -> speak(retry_prompt)
      end

      # Validate a credit card number (Luhn check)
      case DataCollection.collect_credit_card("4111111111111111") do
        {:ok, _} -> :proceed
        {:error, {reason, retry_prompt}} -> speak(retry_prompt)
      end
  """

  @doc """
  Validates and normalizes a phone number.

  Accepts E.164 format (`+15551234567`), US 10-digit (`5551234567`), or
  US format with dashes/spaces (`555-123-4567`).

  Returns `{:ok, e164}` with the normalized E.164 number, or
  `{:error, {reason, retry_prompt}}`.

  ## Examples

      iex> DataCollection.collect_phone_number("+15551234567")
      {:ok, "+15551234567"}

      iex> DataCollection.collect_phone_number("5551234567")
      {:ok, "+15551234567"}

      iex> DataCollection.collect_phone_number("not-a-number")
      {:error, {:invalid_phone_number, "That doesn't look like a valid phone number. Please say or enter your 10-digit phone number again."}}
  """
  @spec collect_phone_number(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, {atom(), String.t()}}
  def collect_phone_number(input, _opts \\ []) when is_binary(input) do
    digits = String.replace(input, ~r/[\s\-\.\(\)]+/, "")

    cond do
      # Already E.164 with country code
      Regex.match?(~r/^\+1\d{10}$/, digits) ->
        {:ok, digits}

      # E.164 with non-US country code (keep as-is if at least 7 digits after +)
      Regex.match?(~r/^\+\d{7,15}$/, digits) ->
        {:ok, digits}

      # 10-digit US number without country code
      Regex.match?(~r/^\d{10}$/, digits) ->
        {:ok, "+1" <> digits}

      # 11-digit starting with 1 (US with leading 1)
      Regex.match?(~r/^1\d{10}$/, digits) ->
        {:ok, "+" <> digits}

      true ->
        {:error,
         {:invalid_phone_number,
          "That doesn't look like a valid phone number. " <>
            "Please say or enter your 10-digit phone number again."}}
    end
  end

  @doc """
  Validates a credit card number using the Luhn algorithm.

  Strips spaces and dashes before validation. Returns `{:ok, normalized}` with
  the stripped card number (digits only), or `{:error, {reason, retry_prompt}}`.

  ## Examples

      iex> DataCollection.collect_credit_card("4111111111111111")
      {:ok, "4111111111111111"}

      iex> DataCollection.collect_credit_card("4111 1111 1111 1111")
      {:ok, "4111111111111111"}

      iex> DataCollection.collect_credit_card("1234567890123456")
      {:error, {:invalid_card_number, "That card number doesn't appear to be valid. Please try again."}}
  """
  @spec collect_credit_card(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, {atom(), String.t()}}
  def collect_credit_card(input, _opts \\ []) when is_binary(input) do
    digits = String.replace(input, ~r/[\s\-]+/, "")

    cond do
      not Regex.match?(~r/^\d{13,19}$/, digits) ->
        {:error,
         {:invalid_card_number, "That card number doesn't appear to be valid. Please try again."}}

      not luhn_valid?(digits) ->
        {:error,
         {:invalid_card_number, "That card number doesn't appear to be valid. Please try again."}}

      true ->
        {:ok, digits}
    end
  end

  @doc """
  Validates a date string in common formats.

  Accepts:
  - `MM/DD/YYYY` (e.g. `01/15/2025`)
  - `MM-DD-YYYY`
  - `YYYY-MM-DD` (ISO 8601)
  - `MM/DD/YY` (2-digit year, assumed 2000+)

  Returns `{:ok, %Date{}}` on success, or `{:error, {reason, retry_prompt}}`.

  ## Examples

      iex> DataCollection.collect_date("01/15/2025")
      {:ok, ~D[2025-01-15]}

      iex> DataCollection.collect_date("2025-01-15")
      {:ok, ~D[2025-01-15]}

      iex> DataCollection.collect_date("13/45/2025")
      {:error, {:invalid_date, "I didn't catch a valid date. Please say the month, day, and year."}}
  """
  @spec collect_date(String.t(), keyword()) ::
          {:ok, Date.t()} | {:error, {atom(), String.t()}}
  def collect_date(input, _opts \\ []) when is_binary(input) do
    trimmed = String.trim(input)

    retry_message =
      "I didn't catch a valid date. Please say the month, day, and year."

    cond do
      # ISO 8601: YYYY-MM-DD
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, trimmed) ->
        parse_iso_date(trimmed, retry_message)

      # MM/DD/YYYY or MM-DD-YYYY
      match = Regex.run(~r/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$/, trimmed) ->
        [_, month, day, year] = match
        parse_date_parts(year, month, day, retry_message)

      # MM/DD/YY — 2-digit year (assume 2000+)
      match = Regex.run(~r/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2})$/, trimmed) ->
        [_, month, day, year_2] = match
        year = "20" <> String.pad_leading(year_2, 2, "0")
        parse_date_parts(year, month, day, retry_message)

      true ->
        {:error, {:invalid_date, retry_message}}
    end
  end

  @doc """
  Validates an email address.

  Uses a pragmatic regex that covers the vast majority of real-world email
  addresses. Returns `{:ok, normalized_email}` (lowercased) or
  `{:error, {reason, retry_prompt}}`.

  ## Examples

      iex> DataCollection.collect_email("User@Example.COM")
      {:ok, "user@example.com"}

      iex> DataCollection.collect_email("not-an-email")
      {:error, {:invalid_email, "That doesn't look like a valid email address. Please spell it out again."}}
  """
  @spec collect_email(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, {atom(), String.t()}}
  def collect_email(input, _opts \\ []) when is_binary(input) do
    trimmed = input |> String.trim() |> String.downcase()

    # Pragmatic email regex: local@domain.tld
    email_regex = ~r/^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$/

    if Regex.match?(email_regex, trimmed) do
      {:ok, trimmed}
    else
      {:error,
       {:invalid_email,
        "That doesn't look like a valid email address. Please spell it out again."}}
    end
  end

  # Private Helpers

  # Luhn algorithm implementation
  @spec luhn_valid?(String.t()) :: boolean()
  defp luhn_valid?(digits) do
    digits
    |> String.graphemes()
    |> Enum.map(&String.to_integer/1)
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.reduce(0, fn {digit, index}, acc ->
      doubled = if rem(index, 2) == 1, do: digit * 2, else: digit
      adjusted = if doubled > 9, do: doubled - 9, else: doubled
      acc + adjusted
    end)
    |> rem(10) == 0
  end

  @spec parse_iso_date(String.t(), String.t()) ::
          {:ok, Date.t()} | {:error, {atom(), String.t()}}
  defp parse_iso_date(date_string, retry_message) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, {:invalid_date, retry_message}}
    end
  end

  @spec parse_date_parts(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, Date.t()} | {:error, {atom(), String.t()}}
  defp parse_date_parts(year, month, day, retry_message) do
    padded =
      "#{String.pad_leading(year, 4, "0")}-#{String.pad_leading(month, 2, "0")}-#{String.pad_leading(day, 2, "0")}"

    case Date.from_iso8601(padded) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, {:invalid_date, retry_message}}
    end
  end
end

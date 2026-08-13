defmodule Livekit.Agents.Telephony.DataCollectionTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.Telephony.DataCollection

  # ---------------------------------------------------------------------------
  # collect_phone_number/1
  # ---------------------------------------------------------------------------

  describe "collect_phone_number/1 — valid inputs" do
    test "accepts E.164 US number" do
      assert {:ok, "+15551234567"} = DataCollection.collect_phone_number("+15551234567")
    end

    test "accepts 10-digit US number without country code" do
      assert {:ok, "+15551234567"} = DataCollection.collect_phone_number("5551234567")
    end

    test "accepts 11-digit US number with leading 1" do
      assert {:ok, "+15551234567"} = DataCollection.collect_phone_number("15551234567")
    end

    test "strips dashes from formatted US number" do
      assert {:ok, "+15551234567"} = DataCollection.collect_phone_number("555-123-4567")
    end

    test "strips spaces from number" do
      assert {:ok, "+15551234567"} = DataCollection.collect_phone_number("555 123 4567")
    end

    test "strips parentheses and spaces from number" do
      assert {:ok, "+15551234567"} = DataCollection.collect_phone_number("(555) 123-4567")
    end

    test "accepts non-US E.164 number" do
      assert {:ok, "+447700900123"} = DataCollection.collect_phone_number("+447700900123")
    end

    test "accepts short international number (7 digits)" do
      assert {:ok, "+1234567"} = DataCollection.collect_phone_number("+1234567")
    end
  end

  describe "collect_phone_number/1 — invalid inputs" do
    test "rejects clearly invalid string" do
      assert {:error, {:invalid_phone_number, retry_prompt}} =
               DataCollection.collect_phone_number("not-a-number")

      assert is_binary(retry_prompt)
      assert String.length(retry_prompt) > 0
    end

    test "rejects too-short number" do
      assert {:error, {:invalid_phone_number, _}} = DataCollection.collect_phone_number("123")
    end

    test "rejects empty string" do
      assert {:error, {:invalid_phone_number, _}} = DataCollection.collect_phone_number("")
    end

    test "rejects number with letters" do
      assert {:error, {:invalid_phone_number, _}} =
               DataCollection.collect_phone_number("555-CALL-NOW")
    end
  end

  # ---------------------------------------------------------------------------
  # collect_credit_card/1
  # ---------------------------------------------------------------------------

  describe "collect_credit_card/1 — valid inputs" do
    # Visa test card
    test "accepts Visa test card number" do
      assert {:ok, "4111111111111111"} = DataCollection.collect_credit_card("4111111111111111")
    end

    # Mastercard test card
    test "accepts Mastercard test card number" do
      assert {:ok, "5500005555555559"} = DataCollection.collect_credit_card("5500005555555559")
    end

    # Amex test card
    test "accepts Amex test card number" do
      assert {:ok, "378282246310005"} = DataCollection.collect_credit_card("378282246310005")
    end

    test "strips spaces from card number" do
      assert {:ok, "4111111111111111"} =
               DataCollection.collect_credit_card("4111 1111 1111 1111")
    end

    test "strips dashes from card number" do
      assert {:ok, "4111111111111111"} =
               DataCollection.collect_credit_card("4111-1111-1111-1111")
    end
  end

  describe "collect_credit_card/1 — invalid inputs" do
    test "rejects card failing Luhn check" do
      assert {:error, {:invalid_card_number, retry_prompt}} =
               DataCollection.collect_credit_card("1234567890123456")

      assert is_binary(retry_prompt)
      assert String.length(retry_prompt) > 0
    end

    test "rejects too-short card number" do
      assert {:error, {:invalid_card_number, _}} = DataCollection.collect_credit_card("12345")
    end

    test "rejects too-long card number" do
      assert {:error, {:invalid_card_number, _}} =
               DataCollection.collect_credit_card("12345678901234567890")
    end

    test "rejects non-numeric input" do
      assert {:error, {:invalid_card_number, _}} =
               DataCollection.collect_credit_card("ABCD-EFGH-IJKL-MNOP")
    end

    test "rejects empty string" do
      assert {:error, {:invalid_card_number, _}} = DataCollection.collect_credit_card("")
    end

    test "rejects sequential digits (fails Luhn)" do
      # 1234567890123456 does not satisfy the Luhn checksum
      assert {:error, {:invalid_card_number, _}} =
               DataCollection.collect_credit_card("1234567890123456")
    end
  end

  # ---------------------------------------------------------------------------
  # collect_date/1
  # ---------------------------------------------------------------------------

  describe "collect_date/1 — valid inputs" do
    test "parses ISO 8601 date" do
      assert {:ok, ~D[2025-01-15]} = DataCollection.collect_date("2025-01-15")
    end

    test "parses MM/DD/YYYY" do
      assert {:ok, ~D[2025-01-15]} = DataCollection.collect_date("01/15/2025")
    end

    test "parses M/D/YYYY (no padding)" do
      assert {:ok, ~D[2025-01-05]} = DataCollection.collect_date("1/5/2025")
    end

    test "parses MM-DD-YYYY with dashes" do
      assert {:ok, ~D[2025-06-30]} = DataCollection.collect_date("06-30-2025")
    end

    test "parses MM/DD/YY with 2-digit year" do
      assert {:ok, ~D[2025-03-20]} = DataCollection.collect_date("03/20/25")
    end

    test "handles whitespace around date" do
      assert {:ok, ~D[2025-01-15]} = DataCollection.collect_date("  2025-01-15  ")
    end
  end

  describe "collect_date/1 — invalid inputs" do
    test "rejects invalid month 13" do
      assert {:error, {:invalid_date, retry_prompt}} = DataCollection.collect_date("13/45/2025")
      assert is_binary(retry_prompt)
    end

    test "rejects invalid day 45" do
      assert {:error, {:invalid_date, _}} = DataCollection.collect_date("01/45/2025")
    end

    test "rejects free-form text" do
      assert {:error, {:invalid_date, _}} = DataCollection.collect_date("next Monday")
    end

    test "rejects empty string" do
      assert {:error, {:invalid_date, _}} = DataCollection.collect_date("")
    end

    test "rejects date with invalid ISO format" do
      assert {:error, {:invalid_date, _}} = DataCollection.collect_date("2025-13-01")
    end
  end

  # ---------------------------------------------------------------------------
  # collect_email/1
  # ---------------------------------------------------------------------------

  describe "collect_email/1 — valid inputs" do
    test "accepts standard email" do
      assert {:ok, "user@example.com"} = DataCollection.collect_email("user@example.com")
    end

    test "normalizes to lowercase" do
      assert {:ok, "user@example.com"} = DataCollection.collect_email("User@Example.COM")
    end

    test "accepts email with dots in local part" do
      assert {:ok, "first.last@example.com"} =
               DataCollection.collect_email("first.last@example.com")
    end

    test "accepts email with plus sign" do
      assert {:ok, "user+tag@example.com"} = DataCollection.collect_email("user+tag@example.com")
    end

    test "accepts email with subdomain" do
      assert {:ok, "user@mail.example.com"} =
               DataCollection.collect_email("user@mail.example.com")
    end

    test "accepts email with hyphens in domain" do
      assert {:ok, "user@my-company.com"} = DataCollection.collect_email("user@my-company.com")
    end

    test "trims leading/trailing whitespace" do
      assert {:ok, "user@example.com"} = DataCollection.collect_email("  user@example.com  ")
    end

    test "accepts long TLD" do
      assert {:ok, "user@example.technology"} =
               DataCollection.collect_email("user@example.technology")
    end
  end

  describe "collect_email/1 — invalid inputs" do
    test "rejects email missing @" do
      assert {:error, {:invalid_email, retry_prompt}} =
               DataCollection.collect_email("not-an-email")

      assert is_binary(retry_prompt)
      assert String.length(retry_prompt) > 0
    end

    test "rejects email missing domain" do
      assert {:error, {:invalid_email, _}} = DataCollection.collect_email("user@")
    end

    test "rejects email missing TLD" do
      assert {:error, {:invalid_email, _}} = DataCollection.collect_email("user@example")
    end

    test "rejects email missing local part" do
      assert {:error, {:invalid_email, _}} = DataCollection.collect_email("@example.com")
    end

    test "rejects empty string" do
      assert {:error, {:invalid_email, _}} = DataCollection.collect_email("")
    end

    test "rejects plain string with spaces" do
      assert {:error, {:invalid_email, _}} =
               DataCollection.collect_email("user name @ example .com")
    end
  end
end

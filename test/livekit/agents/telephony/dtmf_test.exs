defmodule Livekit.Agents.Telephony.DTMFTest do
  use ExUnit.Case, async: true

  alias Livekit.Agents.Telephony.DTMF
  alias Livekit.Agents.Telephony.DTMF.DTMFEvent

  describe "parse_dtmf/1 — binary JSON input" do
    test "parses valid digit with duration" do
      payload = ~s({"digit":"5","duration_ms":100})

      assert {:ok, %DTMFEvent{} = event} = DTMF.parse_dtmf(payload)
      assert event.digit == "5"
      assert event.duration_ms == 100
      assert %DateTime{} = event.timestamp
    end

    test "parses all valid digits 0-9" do
      for digit <- ~w(0 1 2 3 4 5 6 7 8 9) do
        payload = ~s({"digit":"#{digit}"})
        assert {:ok, %DTMFEvent{digit: ^digit}} = DTMF.parse_dtmf(payload)
      end
    end

    test "parses * (star) digit" do
      assert {:ok, %DTMFEvent{digit: "*"}} = DTMF.parse_dtmf(~s({"digit":"*"}))
    end

    test "parses # (pound) digit" do
      assert {:ok, %DTMFEvent{digit: "#"}} = DTMF.parse_dtmf(~s({"digit":"#"}))
    end

    test "parses digit without duration_ms" do
      assert {:ok, %DTMFEvent{digit: "3", duration_ms: nil}} = DTMF.parse_dtmf(~s({"digit":"3"}))
    end

    test "returns invalid_json for non-JSON binary" do
      assert {:error, :invalid_json} = DTMF.parse_dtmf("not json at all")
    end

    test "returns invalid_digit for invalid digit value" do
      assert {:error, :invalid_digit} = DTMF.parse_dtmf(~s({"digit":"Q"}))
      assert {:error, :invalid_digit} = DTMF.parse_dtmf(~s({"digit":"10"}))
      assert {:error, :invalid_digit} = DTMF.parse_dtmf(~s({"digit":"A"}))
    end
  end

  describe "parse_dtmf/1 — map input" do
    test "parses map with digit key" do
      assert {:ok, %DTMFEvent{digit: "7"}} = DTMF.parse_dtmf(%{"digit" => "7"})
    end

    test "parses map with duration_ms" do
      assert {:ok, %DTMFEvent{digit: "1", duration_ms: 250}} =
               DTMF.parse_dtmf(%{"digit" => "1", "duration_ms" => 250})
    end

    test "returns missing_digit for map without digit key" do
      assert {:error, :missing_digit} = DTMF.parse_dtmf(%{"tone" => "5"})
    end

    test "returns invalid_digit for invalid digit in map" do
      assert {:error, :invalid_digit} = DTMF.parse_dtmf(%{"digit" => "Z"})
    end
  end

  describe "collect_digits/2" do
    test "collects digits until # terminator" do
      events = [
        %DTMFEvent{digit: "1", timestamp: DateTime.utc_now()},
        %DTMFEvent{digit: "2", timestamp: DateTime.utc_now()},
        %DTMFEvent{digit: "3", timestamp: DateTime.utc_now()},
        %DTMFEvent{digit: "#", timestamp: DateTime.utc_now()}
      ]

      assert {:ok, "123"} = DTMF.collect_digits(events)
    end

    test "terminator is not included in result" do
      events = [%DTMFEvent{digit: "5"}, %DTMFEvent{digit: "#"}]
      assert {:ok, "5"} = DTMF.collect_digits(events)
    end

    test "returns no_terminator when # never appears" do
      events = [
        %DTMFEvent{digit: "1"},
        %DTMFEvent{digit: "2"},
        %DTMFEvent{digit: "3"}
      ]

      assert {:error, :no_terminator} = DTMF.collect_digits(events)
    end

    test "accepts plain digit strings" do
      assert {:ok, "42"} = DTMF.collect_digits(["4", "2", "#"])
    end

    test "custom terminator" do
      events = ["1", "2", "3", "*", "4"]
      assert {:ok, "123"} = DTMF.collect_digits(events, terminator: "*")
    end

    test "respects max_digits option" do
      digits = Enum.map(1..15, &to_string/1) ++ ["#"]
      # max_digits = 5 stops before reaching #
      assert {:ok, result} = DTMF.collect_digits(digits, max_digits: 5)
      assert String.length(result) == 5
    end

    test "stops at max_digits even without terminator" do
      digits = ~w(1 2 3 4 5 6 7 8 9 0)
      assert {:ok, "12345"} = DTMF.collect_digits(digits, max_digits: 5)
    end

    test "returns empty string when terminator is first" do
      assert {:ok, ""} = DTMF.collect_digits(["#"])
    end

    test "returns no_terminator for empty list" do
      assert {:error, :no_terminator} = DTMF.collect_digits([])
    end

    test "mixes DTMFEvent structs and strings" do
      events = [%DTMFEvent{digit: "9"}, "8", %DTMFEvent{digit: "#"}]
      assert {:ok, "98"} = DTMF.collect_digits(events)
    end

    test "ignores invalid digit values in mixed list" do
      events = [%DTMFEvent{digit: "1"}, "invalid", %DTMFEvent{digit: "2"}, "#"]
      assert {:ok, "12"} = DTMF.collect_digits(events)
    end
  end
end

defmodule Livekit.UtilsTest do
  use ExUnit.Case
  alias Livekit.Utils

  describe "to_http_url/1" do
    test "converts ws:// to http://" do
      assert Utils.to_http_url("ws://example.com") == "http://example.com"
    end

    test "converts wss:// to https://" do
      assert Utils.to_http_url("wss://example.com") == "https://example.com"
    end

    test "adds http:// to bare URLs" do
      assert Utils.to_http_url("example.com") == "http://example.com"
    end

    test "leaves http:// URLs unchanged" do
      assert Utils.to_http_url("http://example.com") == "http://example.com"
    end

    test "leaves https:// URLs unchanged" do
      assert Utils.to_http_url("https://example.com") == "https://example.com"
    end
  end

  describe "random_string/1" do
    test "generates string of correct length" do
      length = 16
      result = Utils.random_string(length)
      assert String.length(result) == length
    end

    test "generates different strings" do
      string1 = Utils.random_string(16)
      string2 = Utils.random_string(16)
      refute string1 == string2
    end

    test "generates URL-safe strings" do
      string = Utils.random_string(32)
      assert String.match?(string, ~r/^[A-Za-z0-9\-_]+$/)
    end
  end
end

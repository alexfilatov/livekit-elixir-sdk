defmodule LiveKit.ConfigTest do
  use ExUnit.Case
  alias LiveKit.Config

  describe "get/1" do
    test "returns config with runtime options" do
      opts = [
        url: "wss://test.com",
        api_key: "runtime_key",
        api_secret: "runtime_secret"
      ]

      config = Config.get(opts)
      assert config.url == "wss://test.com"
      assert config.api_key == "runtime_key"
      assert config.api_secret == "runtime_secret"
    end

    test "returns config with application env" do
      url = "wss://app-env.com"
      api_key = "app_env_key"
      api_secret = "app_env_secret"

      Application.put_env(:livekit, :url, url)
      Application.put_env(:livekit, :api_key, api_key)
      Application.put_env(:livekit, :api_secret, api_secret)

      config = Config.get([])
      assert config.url == url
      assert config.api_key == api_key
      assert config.api_secret == api_secret

      # Cleanup
      Application.delete_env(:livekit, :url)
      Application.delete_env(:livekit, :api_key)
      Application.delete_env(:livekit, :api_secret)
    end

    test "runtime options override application env" do
      Application.put_env(:livekit, :url, "wss://app-env.com")
      Application.put_env(:livekit, :api_key, "app_env_key")
      Application.put_env(:livekit, :api_secret, "app_env_secret")

      opts = [url: "wss://override.com"]
      config = Config.get(opts)

      assert config.url == "wss://override.com"
      assert config.api_key == "app_env_key"
      assert config.api_secret == "app_env_secret"

      # Cleanup
      Application.delete_env(:livekit, :url)
      Application.delete_env(:livekit, :api_key)
      Application.delete_env(:livekit, :api_secret)
    end
  end

  describe "validate/1" do
    test "returns :ok for valid config" do
      config = %Config{
        url: "wss://test.com",
        api_key: "test_key",
        api_secret: "test_secret"
      }

      assert :ok = Config.validate(config)
    end

    test "returns error for missing url" do
      config = %Config{
        api_key: "test_key",
        api_secret: "test_secret"
      }

      assert {:error, "LiveKit URL is required"} = Config.validate(config)
    end

    test "returns error for missing api_key" do
      config = %Config{
        url: "wss://test.com",
        api_secret: "test_secret"
      }

      assert {:error, "LiveKit API key is required"} = Config.validate(config)
    end

    test "returns error for missing api_secret" do
      config = %Config{
        url: "wss://test.com",
        api_key: "test_key"
      }

      assert {:error, "LiveKit API secret is required"} = Config.validate(config)
    end
  end
end

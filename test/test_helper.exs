ExUnit.start()

# Set up test configuration
Application.put_env(:livekit, :url, "wss://test.livekit.com")
Application.put_env(:livekit, :api_key, "test_key")
Application.put_env(:livekit, :api_secret, "test_secret")

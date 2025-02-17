import Config

config :livekit,
  url: System.get_env("LIVEKIT_URL"),
  api_key: System.get_env("LIVEKIT_API_KEY"),
  api_secret: System.get_env("LIVEKIT_API_SECRET")

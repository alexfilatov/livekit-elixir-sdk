import Config

# Configure logger for test environment
config :logger,
  level: :info,
  format: {Livekit.TestFormatter, :format}

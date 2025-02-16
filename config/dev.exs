import Config

# Configure logger for development environment
config :logger,
  level: :debug,
  format: "$time $metadata[$level] $message\n"

# Configure Tesla logger middleware for development
config :livekit, LiveKit.RoomServiceClient,
  tesla_logging: [
    # Enable debug logging in development
    debug: true,
    # Filter out sensitive headers
    filter_headers: ["authorization"],
    # Don't log binary data
    format_options: [
      format_response_body: false,
      format_request_body: false
    ]
  ]

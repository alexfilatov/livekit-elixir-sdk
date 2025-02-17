import Config

# Configure logger for production environment
config :logger,
  level: :info,
  format: :json,
  backends: [:console],
  compile_time_purge_matching: [
    # Only log info and above in production
    [level_lower_than: :info]
  ]

# Configure Tesla logger middleware for production
config :livekit, LiveKit.RoomServiceClient,
  tesla_logging: [
    # Disable debug logging in production
    debug: false,
    # Filter out sensitive headers
    filter_headers: ["authorization"],
    # Don't log binary data
    format_options: [
      format_response_body: false,
      format_request_body: false
    ]
  ]

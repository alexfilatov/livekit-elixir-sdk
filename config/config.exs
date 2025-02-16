import Config

config :joken,
  default_signer: [
    signer_alg: "HS256"
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

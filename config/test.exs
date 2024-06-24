import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :rtc, RtcWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "qUMD4asUeZm2NDtdiDUS1DtbYJ/W0spBc/iEdw9fvaqQ2OcUZuE5e7OV3KIo5vaB",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true

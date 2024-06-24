# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :rtc,
  generators: [timestamp_type: :utc_datetime]

config :porcelain, driver: Porcelain.Driver.Basic
config :nx, :default_backend, EXLA.Backend

config :rtc, :ffmpeg, System.find_executable("FFMPEG")

config :rtc, :hls,
  dash_dir: System.get_env("DASH_DIR"),
  hls_dir: System.get_env("HLS_DIR"),
  tmp_dir: System.get_env("TMP_DIR"),
  every: 20

config :rtc, :models,
  haar_cascade: System.get_env("HAAR_CASCADE"),
  face_api: System.get_env("FACE_API")

# config :rtc, :hls,
#   dash_dir: "priv/static/dash/",
#   hls_dir: "priv/static/hls/",
#   tmp_dir: "priv/static/tmp/",
#   every: 20

# config :rtc, :models,
#   haar_cascade: "priv/static/models/opencv_haar/haarcascade_frontalface_default.xml",
#   face_api: "priv/static/models/face-api/"

# Configures the endpoint
config :rtc, RtcWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: RtcWeb.ErrorHTML, json: RtcWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Rtc.PubSub,
  live_view: [signing_salt: "+NmMAJnT"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.21.4",
  rtc: [
    args:
      ~w(js/app.js --bundle --format=esm --target=es2022 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.0",
  rtc: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

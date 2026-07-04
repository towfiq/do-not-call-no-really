# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :dnc_watchdog,
  ecto_repos: [DncWatchdog.Repo],
  generators: [timestamp_type: :utc_datetime]

# Periodic local import (disabled by default). When enabled, runs while `mix phx.server` is up.
# Duplicate communications are skipped via fingerprint deduplication.
config :dnc_watchdog, :periodic_import,
  enabled: false,
  interval_ms: 900_000,
  lookback_days: 7,
  limit: 2_000,
  skip_contacts: true,
  skip_self_initiated: true,
  run_on_start: true

config :dnc_watchdog, :periodic_tracking_refresh,
  enabled: false,
  interval_ms: 3_600_000,
  run_on_start: false

# Configures the endpoint
config :dnc_watchdog, DncWatchdogWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DncWatchdogWeb.ErrorHTML, json: DncWatchdogWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: DncWatchdog.PubSub,
  live_view: [signing_salt: "puVBvGU1"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :dnc_watchdog, DncWatchdog.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  dnc_watchdog: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  dnc_watchdog: [
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

config :chromic_pdf,
  offline: true,
  no_sandbox: true,
  session_pool: %{
    default: [
      timeout: 30_000,
      init_timeout: 30_000,
      checkout_timeout: 30_000
    ],
    online: [
      size: 1,
      offline: false,
      timeout: 45_000,
      init_timeout: 45_000,
      checkout_timeout: 45_000
    ]
  }

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

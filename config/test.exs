import Config

sqlite_defaults = [
  busy_timeout: 5_000,
  journal_mode: :wal
]

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :dnc_watchdog, DncWatchdog.Repo,
  [
    database:
      Path.expand(
        "../priv/repo/dnc_watchdog_test#{System.get_env("MIX_TEST_PARTITION")}.db",
        __DIR__
      ),
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2
  ] ++ sqlite_defaults

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :dnc_watchdog, DncWatchdogWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "C+oDQWNyil3AMPmHBSI8x9X96u1wO3KXaPdOFuBaaXA/MZ+77oYe2AwuYf8qXN0y",
  server: false

# In test we don't send emails
config :dnc_watchdog, DncWatchdog.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

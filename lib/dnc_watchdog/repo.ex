defmodule DncWatchdog.Repo do
  use Ecto.Repo,
    otp_app: :dnc_watchdog,
    adapter: Ecto.Adapters.SQLite3
end

defmodule DncWatchdog.Enforcement.PeriodicTrackingRefresh do
  @moduledoc """
  Periodically refreshes USPS tracking status for cases with open mail tracking.

  Enable via config:

      config :dnc_watchdog, :periodic_tracking_refresh,
        enabled: true,
        interval_ms: 3_600_000

  Requires Google Chrome or Chromium (same as PDF export).
  """

  use GenServer

  require Logger

  alias DncWatchdog.Enforcement

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(config) do
    interval_ms = Keyword.get(config, :interval_ms, 3_600_000)
    run_on_start? = Keyword.get(config, :run_on_start, false)
    delay = if run_on_start?, do: 10_000, else: interval_ms

    Process.send_after(self(), :refresh, delay)

    {:ok, %{config: config, interval_ms: interval_ms}}
  end

  @impl true
  def handle_info(:refresh, state) do
    summary = Enforcement.refresh_all_mail_tracking()

    Logger.info(
      "[PeriodicTrackingRefresh] checked=#{summary.checked} updated=#{summary.updated} " <>
        "errors=#{summary.errors}"
    )

    Process.send_after(self(), :refresh, state.interval_ms)
    {:noreply, state}
  end
end

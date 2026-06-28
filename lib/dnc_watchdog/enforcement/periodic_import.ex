defmodule DncWatchdog.Enforcement.PeriodicImport do
  @moduledoc """
  Runs `LocalImporter` on an interval while the application is up.

  Enable via config:

      config :dnc_watchdog, :periodic_import,
        enabled: true,
        interval_ms: 900_000,
        lookback_days: 7

  Duplicate rows are skipped automatically via communication fingerprints.
  """

  use GenServer

  require Logger

  alias DncWatchdog.Enforcement.LocalImportOptions
  alias DncWatchdog.Enforcement.LocalImporter

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(config) do
    interval_ms = Keyword.get(config, :interval_ms, 900_000)
    run_on_start? = Keyword.get(config, :run_on_start, true)
    delay = if run_on_start?, do: 5_000, else: interval_ms

    Process.send_after(self(), :import, delay)

    {:ok, %{config: config, interval_ms: interval_ms}}
  end

  @impl true
  def handle_info(:import, state) do
    opts = LocalImportOptions.from_config(state.config)
    summary = LocalImporter.import_local(opts)

    Logger.info(
      "[PeriodicImport] lookback=#{format_lookback(opts)} " <>
        "read=#{summary.message_rows + summary.call_rows} " <>
        "new=#{summary.created_communications} " <>
        "duplicates=#{Map.get(summary, :skipped_duplicates, 0)} " <>
        "lookback_skipped=#{Map.get(summary, :skipped_lookback, 0)}"
    )

    for {:error, module, path, reason} <- summary.logs do
      Logger.warning("[PeriodicImport] #{inspect(module)} (#{path}): #{reason}")
    end

    Process.send_after(self(), :import, state.interval_ms)
    {:noreply, state}
  end

  defp format_lookback(opts) do
    case {Keyword.get(opts, :lookback_days), Keyword.get(opts, :since)} do
      {days, _} when is_integer(days) -> "#{days}d"
      {_, %NaiveDateTime{} = since} -> NaiveDateTime.to_iso8601(since)
      _ -> "all"
    end
  end
end

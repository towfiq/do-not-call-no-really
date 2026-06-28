defmodule Mix.Tasks.Dnc.ImportFromPostgres do
  use Mix.Task

  @shortdoc "Copy all data from PostgreSQL into the local SQLite database"

  @moduledoc """
  Copies application tables from a PostgreSQL database into the configured SQLite repo.

  Existing SQLite rows in those tables are replaced. Primary keys and foreign keys
  are preserved so cases, communications, and evidence stay linked.

  ## Options

  Environment variables for the source PostgreSQL database (defaults match the old dev setup):

      PGHOST=localhost
      PGUSER=postgres
      PGPASSWORD=postgres
      PGDATABASE=dnc_watchdog_dev

  ## Examples

      mix dnc.import_from_postgres
  """

  alias DncWatchdog.Enforcement.PostgresImporter

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    summary = PostgresImporter.import_all()

    Mix.shell().info("Imported #{summary.total_rows} rows from PostgreSQL into SQLite:")
    Mix.shell().info("")

    Enum.each(summary.tables, fn {table, count} ->
      Mix.shell().info("  #{table}: #{count}")
    end)

    Mix.shell().info("")
    Mix.shell().info("SQLite database: #{sqlite_path()}")
  end

  defp sqlite_path do
    Application.fetch_env!(:dnc_watchdog, DncWatchdog.Repo)
    |> Keyword.fetch!(:database)
  end
end

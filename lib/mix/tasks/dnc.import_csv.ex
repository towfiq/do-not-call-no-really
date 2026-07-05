defmodule Mix.Tasks.Dnc.ImportCsv do
  use Mix.Task

  @shortdoc "Import communication records from CSV"

  @impl Mix.Task
  def run([csv_path]) do
    Mix.Task.run("app.start")

    summary = DncWatchdog.Enforcement.Importer.import_csv(csv_path)

    Mix.shell().info("CSV rows imported: #{summary.rows}")
    Mix.shell().info("New cases created: #{summary.created_cases}")
    Mix.shell().info("Communications stored: #{summary.created_communications}")
    Mix.shell().info("Duplicates skipped: #{Map.get(summary, :skipped_duplicates, 0)}")
    Mix.shell().info("")

    Mix.shell().info(
      "Note: multiple CSV rows with the same company (or blank company) attach to one case."
    )
  end

  def run(_) do
    Mix.shell().error("Usage: mix dnc.import_csv path/to/communications.csv")
  end
end

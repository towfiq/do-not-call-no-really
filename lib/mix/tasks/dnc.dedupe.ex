defmodule Mix.Tasks.Dnc.Dedupe do
  use Mix.Task

  @shortdoc "Remove duplicate communications and backfill fingerprints"

  @switches [dry_run: :boolean]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, [], []} = OptionParser.parse(argv, switches: @switches)
    dry_run? = Keyword.get(opts, :dry_run, false)

    summary = DncWatchdog.Enforcement.Dedupe.dedupe_communications(dry_run: dry_run?)

    if dry_run? do
      Mix.shell().info("Dry run — no rows deleted or updated.")
    end

    Mix.shell().info("Communications scanned: #{summary.total}")
    Mix.shell().info("Duplicate groups: #{summary.duplicate_groups}")
    Mix.shell().info("Rows removed: #{summary.deleted}")
    Mix.shell().info("Fingerprints backfilled: #{summary.fingerprints_backfilled}")
  end
end

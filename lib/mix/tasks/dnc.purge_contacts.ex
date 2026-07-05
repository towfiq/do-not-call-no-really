defmodule Mix.Tasks.Dnc.PurgeContacts do
  use Mix.Task

  @shortdoc "Remove communications from macOS Contacts that were imported earlier"

  @switches [dry_run: :boolean, contacts_db: :string]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, [], []} = OptionParser.parse(argv, switches: @switches)
    dry_run? = Keyword.get(opts, :dry_run, false)

    import_opts =
      opts
      |> Keyword.take([:contacts_db])
      |> Keyword.put(:dry_run, dry_run?)

    case DncWatchdog.Enforcement.PurgeContacts.purge(import_opts) do
      {:error, :contacts_not_found} ->
        Mix.shell().error(
          "No Contacts databases found under ~/Library/Application Support/AddressBook."
        )

        System.halt(1)

      {:error, :contacts_empty} ->
        Mix.shell().error(
          "Contacts databases were found but no phone numbers or emails were loaded."
        )

        System.halt(1)

      {:error, {:contacts_unreadable, errors}} ->
        Mix.shell().error("Could not read Contacts databases:")

        Enum.each(errors, fn {path, reason} ->
          Mix.shell().error("  #{path}: #{inspect(reason)}")
        end)

        Mix.shell().error("Grant Full Disk Access to Terminal or Cursor and try again.")
        System.halt(1)

      {:error, reason} ->
        Mix.shell().error("Purge failed: #{inspect(reason)}")
        System.halt(1)

      {:ok, summary} ->
        if dry_run? do
          Mix.shell().info("Dry run — no rows deleted.")
        end

        Mix.shell().info("Communications scanned: #{summary.total}")
        Mix.shell().info("Matched macOS Contacts: #{summary.matched}")
        Mix.shell().info("Communications removed: #{summary.deleted}")
        Mix.shell().info("Empty cases removed: #{summary.cases_deleted}")
        Mix.shell().info("Remaining: #{summary.remaining}")
    end
  end
end

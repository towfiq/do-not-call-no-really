defmodule Mix.Tasks.Dnc.RemoveOutgoing do
  use Mix.Task

  @shortdoc "Remove outgoing calls and texts you initiated from the database"

  @switches [dry_run: :boolean, my_phone: :string]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, [], []} = OptionParser.parse(argv, switches: @switches)
    dry_run? = Keyword.get(opts, :dry_run, false)

    case DncWatchdog.Enforcement.PurgeSelfInitiated.purge(
           dry_run: dry_run?,
           my_phone: Keyword.get(opts, :my_phone)
         ) do
      {:error, :my_phone_required} ->
        Mix.shell().error("Set DNC_MY_PHONE or pass --my-phone (e.g. --my-phone 4159719595)")
        System.halt(1)

      {:ok, summary} ->
        if dry_run? do
          Mix.shell().info("Dry run — no rows deleted.")
        end

        Mix.shell().info("Communications scanned: #{summary.total}")
        Mix.shell().info("Outgoing / self-initiated matched: #{summary.matched}")
        Mix.shell().info("Rows removed: #{summary.deleted}")
        Mix.shell().info("Remaining: #{summary.remaining}")
    end
  end
end

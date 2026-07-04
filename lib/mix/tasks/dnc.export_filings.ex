defmodule Mix.Tasks.Dnc.ExportFilings do
  use Mix.Task

  @shortdoc "Export small-claims filing drafts from case records"

  @switches [pdf: :boolean]
  @aliases [p: :pdf]

  @impl Mix.Task
  def run(args) do
    {opts, positional} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    case positional do
      [output_dir] ->
        Mix.Task.run("app.start")

        outputs =
          DncWatchdog.Enforcement.CourtFilingExporter.export_all(output_dir, pdf: opts[:pdf])

        Mix.shell().info("Filing drafts generated: #{Enum.count(outputs)}")
        Enum.each(outputs, &Mix.shell().info("- #{&1}"))

      _ ->
        usage()
    end
  end

  defp usage do
    Mix.shell().error("Usage: mix dnc.export_filings output/filings [--pdf]")
  end
end

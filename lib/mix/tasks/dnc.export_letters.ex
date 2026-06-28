defmodule Mix.Tasks.Dnc.ExportLetters do
  use Mix.Task

  @shortdoc "Export demand letters from case records"

  @switches [pdf: :boolean]
  @aliases [p: :pdf]

  @impl Mix.Task
  def run(args) do
    {opts, positional} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    case positional do
      [output_dir, your_name, your_phone, dnc_date] ->
        Mix.Task.run("app.start")

        outputs =
          DncWatchdog.Enforcement.LetterExporter.export_all(
            output_dir,
            your_name,
            your_phone,
            dnc_date,
            pdf: opts[:pdf]
          )

        Mix.shell().info("Letters generated: #{Enum.count(outputs)}")
        Enum.each(outputs, &Mix.shell().info("- #{&1}"))

      _ ->
        usage()
    end
  end

  defp usage do
    Mix.shell().error(
      "Usage: mix dnc.export_letters output/letters \"Your Name\" \"+1-555-000-1234\" 2020-01-01 [--pdf]"
    )
  end
end

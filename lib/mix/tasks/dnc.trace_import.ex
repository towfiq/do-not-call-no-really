defmodule Mix.Tasks.Dnc.TraceImport do
  use Mix.Task

  @shortdoc "Trace why a phone number is or is not imported from chat.db"

  @switches [lookback_days: :integer, my_phone: :string, limit: :integer]

  @impl Mix.Task
  def run(args) do
    {opts, args, _} = OptionParser.parse(args, strict: @switches)
    phone = List.first(args)

    if is_nil(phone) or phone == "" do
      Mix.shell().error("Usage: mix dnc.trace_import 8187432556 [--lookback-days 60]")
      exit({:shutdown, 1})
    end

    Mix.Task.run("app.start")

    import_opts =
      opts
      |> Keyword.put_new(:lookback_days, 60)
      |> DncWatchdog.Enforcement.LocalImportOptions.build()

    path = DncWatchdog.Enforcement.Local.Paths.messages_db(Keyword.get(import_opts, :messages_db))
    digits = DncWatchdog.Enforcement.Phone.normalize(phone)

    Mix.shell().info("Tracing #{digits} with lookback_days=#{import_opts[:lookback_days]}")
    Mix.shell().info("Messages DB: #{path}")
    Mix.shell().info("")

    case DncWatchdog.Enforcement.Local.Messages.read(path, import_opts) do
      {:ok, rows} ->
        matches =
          Enum.filter(rows, fn row -> row.from_number == digits or row.to_number == digits end)

        Mix.shell().info(
          "Messages.read returned #{length(rows)} row(s); #{length(matches)} match #{digits}"
        )

        if matches == [] do
          Mix.shell().info("")
          Mix.shell().info("Not in import batch — likely outside lookback or beyond --limit.")
          Mix.shell().info("Try: mix dnc.find_message #{digits}")
        end

        Enum.each(matches, fn row ->
          Mix.shell().info("")

          Mix.shell().info(
            "#{row.timestamp} #{row.direction} #{row.from_number} -> #{row.to_number}"
          )

          Mix.shell().info("  body: #{String.slice(row.body, 0, 120)}")

          case DncWatchdog.Enforcement.RowImporter.import_row(row) do
            {:ok, %{duplicate: true}} ->
              Mix.shell().info("  import: duplicate (already stored)")

            {:ok, %{duplicate: false}} ->
              Mix.shell().info("  import: stored")

            {:error, %Ecto.Changeset{} = changeset} ->
              Mix.shell().error("  import failed: #{format_changeset_errors(changeset)}")
          end
        end)

      {:error, reason} ->
        Mix.shell().error(inspect(reason))
        exit({:shutdown, 1})
    end
  end

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> inspect()
  end
end

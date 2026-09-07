defmodule Mix.Tasks.Dnc.ImportLocal do
  use Mix.Task

  @shortdoc "Import call/SMS history from local macOS SQLite databases"

  @switches [
    messages: :boolean,
    calls: :boolean,
    skip_contacts: :boolean,
    include_outgoing: :boolean,
    messages_db: :string,
    calls_db: :string,
    contacts_db: :string,
    limit: :integer,
    my_phone: :string,
    lookback_days: :integer
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: @switches)

    Mix.Task.run("app.start")

    include_outgoing? = Keyword.get(opts, :include_outgoing, false)

    import_opts =
      opts
      |> Keyword.merge(
        messages: Keyword.get(opts, :messages, true),
        calls: Keyword.get(opts, :calls, true),
        skip_contacts: Keyword.get(opts, :skip_contacts, true),
        limit: Keyword.get(opts, :limit, 5_000)
      )
      |> DncWatchdog.Enforcement.LocalImportOptions.build()
      |> maybe_skip_self_initiated(include_outgoing?)

    summary = DncWatchdog.Enforcement.LocalImporter.import_local(import_opts)

    if Keyword.get(opts, :limit) && import_opts[:lookback_days] do
      Mix.shell().info(
        "Note: --limit is ignored when --lookback-days is set; the time window is the only bound."
      )
    end

    Enum.each(summary.logs, fn
      {:ok, module, path, count} ->
        Mix.shell().info("Read #{count} rows from #{inspect(module)} (#{path})")

      {:error, module, path, reason} ->
        Mix.shell().error("Failed #{inspect(module)} (#{path}): #{format_error(reason)}")

      {:contacts_loaded, phones, emails, paths} ->
        Mix.shell().info(
          "Loaded #{phones} contact phone(s) and #{emails} email(s) from #{length(paths)} database(s)"
        )

      {:contacts_empty, message} ->
        Mix.shell().error(message)

      {:contacts_skipped, message} ->
        Mix.shell().info(message)

      {:contacts_disabled, message} ->
        Mix.shell().info(message)
    end)

    Mix.shell().info("")

    if summary.since do
      Mix.shell().info("Lookback since: #{summary.since}")
    end

    if summary.lookback_days do
      Mix.shell().info("Lookback window: #{summary.lookback_days} day(s)")
    end

    cap = DncWatchdog.Enforcement.LocalImportOptions.sql_row_cap(import_opts)

    Mix.shell().info(
      "SQL row cap: #{if cap == :no_cap, do: "none (lookback active)", else: "LIMIT #{cap}"}"
    )

    Mix.shell().info("Message rows read: #{summary.message_rows}")
    Mix.shell().info("Call rows read: #{summary.call_rows}")
    Mix.shell().info("Skipped (outside lookback): #{Map.get(summary, :skipped_lookback, 0)}")
    Mix.shell().info("Skipped (in Contacts): #{summary.skipped_contacts}")
    Mix.shell().info("Skipped (you initiated): #{Map.get(summary, :skipped_self_initiated, 0)}")
    Mix.shell().info("Rows imported: #{summary.rows}")
    Mix.shell().info("New cases created: #{summary.created_cases}")
    Mix.shell().info("Communications stored: #{summary.created_communications}")
    Mix.shell().info("Duplicates skipped: #{Map.get(summary, :skipped_duplicates, 0)}")

    Mix.shell().info(
      "Skipped (own number as caller): #{Map.get(summary, :skipped_own_number, 0)}"
    )

    Mix.shell().info("Failed to store: #{Map.get(summary, :failed, 0)}")

    if summary.created_communications == 0 and Map.get(summary, :skipped_duplicates, 0) > 0 do
      Mix.shell().info("")

      Mix.shell().info(
        "All rows in this batch were already imported (duplicate fingerprints). " <>
          "A longer lookback only adds rows that are not already in the database."
      )
    end

    if summary.messages_path do
      Mix.shell().info("Messages DB: #{summary.messages_path}")
    end

    if summary.calls_path do
      Mix.shell().info("Call History DB: #{summary.calls_path}")
    end

    Mix.shell().info("")

    Mix.shell().info(
      "Tip: set DNC_MY_PHONE=\"+1...\" and use --lookback-days 7 for incremental imports. Duplicates are skipped automatically. --limit only applies when no lookback is set."
    )
  end

  defp maybe_skip_self_initiated(opts, true), do: Keyword.put(opts, :skip_self_initiated, false)
  defp maybe_skip_self_initiated(opts, false), do: opts

  defp format_error(reason) do
    DncWatchdog.Enforcement.LocalImporter.format_error(reason)
  end
end

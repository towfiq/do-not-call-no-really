defmodule DncWatchdog.Enforcement.LocalImporter do
  @moduledoc """
  Imports communications from local macOS SQLite databases.
  """

  alias DncWatchdog.Enforcement.ContactFilter
  alias DncWatchdog.Enforcement.SelfInitiatedFilter
  alias DncWatchdog.Enforcement.Local.Lookback
  alias DncWatchdog.Enforcement.Local.CallHistory
  alias DncWatchdog.Enforcement.Local.Contacts
  alias DncWatchdog.Enforcement.Local.Messages
  alias DncWatchdog.Enforcement.Local.Paths
  alias DncWatchdog.Enforcement.RowImporter

  def format_error(reason) when is_binary(reason), do: reason

  def format_error({:snapshot_failed, message}) do
    "Could not copy database for safe reading: #{message}"
  end

  def format_error({:source_not_found, path}) do
    "Database not found: #{path}"
  end

  def format_error({:database_open_failed, %{snapshot: snapshot, direct: direct}}) do
    "Could not copy database (#{format_error(snapshot)}) and could not open it directly (#{format_error(direct)})"
  end

  def format_error({:database_open_failed, reason}) do
    "Could not open database read-only: #{format_error(reason)}"
  end

  def format_error({:query_only_failed, reason}) do
    "Could not enable read-only query mode: #{inspect(reason)}"
  end

  def format_error({:query_only_not_enabled, other}) do
    "SQLite query_only was not enabled: #{inspect(other)}"
  end

  def format_error(reason), do: inspect(reason)

  def import_local(opts \\ []) do
    include_messages = Keyword.get(opts, :messages, true)
    include_calls = Keyword.get(opts, :calls, true)
    limit = Keyword.get(opts, :limit)
    my_phone =
      opts
      |> Keyword.get(:my_phone)
      |> DncWatchdog.Enforcement.Phone.normalize_or_env()

    skip_contacts = Keyword.get(opts, :skip_contacts, true)
    skip_self_initiated = Keyword.get(opts, :skip_self_initiated, my_phone != "")
    since = Lookback.since_from_opts(opts)

    {contact_set, contact_log} =
      if skip_contacts do
        contacts_paths =
          case Keyword.get(opts, :contacts_dbs) do
            nil -> Keyword.get(opts, :contacts_db)
            paths -> paths
          end

        case Contacts.load(contacts_dbs: Paths.contacts_dbs(contacts_paths)) do
          {:ok, set, paths} ->
            logs =
              if paths == [] or MapSet.size(set.phones) == 0 and MapSet.size(set.emails) == 0 do
                [
                  {:contacts_loaded, MapSet.size(set.phones), MapSet.size(set.emails), paths},
                  {:contacts_empty,
                   "No contact phones or emails loaded; known contacts will not be filtered. " <>
                     "Check Full Disk Access and run `mix dnc.check_contact <phone>` to diagnose."}
                ]
              else
                [{:contacts_loaded, MapSet.size(set.phones), MapSet.size(set.emails), paths}]
              end

            {set, logs}

          {:error, {:contacts_unreadable, _errors}} ->
            {ContactFilter.empty_set(),
             [
               {:contacts_skipped,
                "Could not read Contacts databases; import continued without contact filtering"}
             ]}
        end
      else
        {ContactFilter.empty_set(), [{:contacts_disabled, "Contact filtering disabled"}]}
      end

    reader_opts = [limit: limit, my_phone: my_phone, since: since, lookback_days: Keyword.get(opts, :lookback_days)]

    {message_rows, messages_path, message_log, message_skipped_lookback} =
      if include_messages do
        path = Paths.messages_db(Keyword.get(opts, :messages_db))
        read_source(Messages, path, reader_opts)
      else
        {[], nil, [], 0}
      end

    {call_rows, calls_path, call_log, call_skipped_lookback} =
      if include_calls do
        path = Paths.call_history_db(Keyword.get(opts, :calls_db))

        if path do
          read_source(CallHistory, path, reader_opts)
        else
          {[],
           nil,
           [
             {:error,
              "Call History database not found. Checked: #{inspect(Paths.default_call_history_paths())}"}
           ],
           0}
        end
      else
        {[], nil, [], 0}
      end

    skipped_lookback = message_skipped_lookback + call_skipped_lookback

    rows = message_rows ++ call_rows
    {rows_after_contacts, skipped_contacts} =
      maybe_filter_contacts(rows, skip_contacts, contact_set)

    {rows_to_import, skipped_self_initiated} =
      maybe_filter_self_initiated(rows_after_contacts, skip_self_initiated, my_phone)

    summary = RowImporter.import_rows(rows_to_import)

    Map.merge(summary, %{
      messages_path: messages_path,
      calls_path: calls_path,
      message_rows: length(message_rows),
      call_rows: length(call_rows),
      skipped_contacts: skipped_contacts,
      skipped_self_initiated: skipped_self_initiated,
      skipped_lookback: skipped_lookback,
      since: since,
      lookback_days: Keyword.get(opts, :lookback_days),
      logs: message_log ++ call_log ++ contact_log
    })
  end

  defp maybe_filter_contacts(rows, true, contact_set) do
    ContactFilter.reject_contacts(rows, contact_set)
  end

  defp maybe_filter_contacts(rows, false, _contact_set), do: {rows, 0}

  defp maybe_filter_self_initiated(rows, true, my_phone) do
    SelfInitiatedFilter.reject_self_initiated(rows, my_phone)
  end

  defp maybe_filter_self_initiated(rows, false, _my_phone), do: {rows, 0}

  defp read_source(module, path, opts) do
    case module.read(path, opts) do
      {:ok, rows} ->
        since = Lookback.since_from_opts(opts)
        {filtered, skipped} = Lookback.filter_rows(rows, since)
        {filtered, path, [{:ok, module, path, length(filtered)}], skipped}

      {:error, reason} ->
        {[], path, [{:error, module, path, format_error(reason)}], 0}
    end
  end
end

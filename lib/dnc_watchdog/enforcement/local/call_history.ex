defmodule DncWatchdog.Enforcement.Local.CallHistory do
  @moduledoc """
  Reads call rows from macOS `CallHistory.storedata`.
  """

  alias DncWatchdog.Enforcement.Local.Lookback
  alias DncWatchdog.Enforcement.Local.Paths
  alias DncWatchdog.Enforcement.Phone
  alias DncWatchdog.Enforcement.Sqlite

  @apple_epoch_seconds 978_307_200

  @doc """
  Diagnoses whether a phone appears in local Call History and what the newest
  readable call timestamp is. Intended for the LiveView probe button.
  """
  def probe(phone, opts \\ []) do
    needle = Phone.normalize(phone)

    paths =
      Paths.default_call_history_paths()
      |> Enum.filter(&File.exists?/1)

    if paths == [] do
      {:error,
       "Call History database not found. Checked: #{inspect(Paths.default_call_history_paths())}"}
    else
      reports =
        Enum.map(paths, fn path ->
          case read(path, opts) do
            {:ok, rows} ->
              newest =
                case rows do
                  [] -> "none"
                  _ -> rows |> Enum.map(& &1.timestamp) |> Enum.max(NaiveDateTime) |> to_string()
                end

              empty =
                Enum.count(rows, fn row ->
                  Phone.normalize(row.from_number) == "" and Phone.normalize(row.to_number) == ""
                end)

              hits =
                Enum.filter(rows, fn row ->
                  Enum.any?([row.from_number, row.to_number, row.company], fn value ->
                    normalized = Phone.normalize(to_string(value || ""))
                    needle != "" and String.contains?(normalized, needle)
                  end)
                end)

              hit_desc =
                case hits do
                  [] ->
                    "0 hits"

                  [hit | _] ->
                    "#{length(hits)} hit(s); first #{hit.timestamp} from=#{hit.from_number} company=#{inspect(hit.company)}"
                end

              "#{Path.basename(path)}: #{length(rows)} rows, newest=#{newest}, empty_peer=#{empty}, #{hit_desc}"

            {:error, reason} ->
              "#{Path.basename(path)}: ERROR #{reason}"
          end
        end)

      {:ok, "Call History probe for #{needle}: " <> Enum.join(reports, " · ")}
    end
  end

  def read(path, opts \\ []) do
    limit = Keyword.get(opts, :limit)
    my_phone = opts |> Keyword.get(:my_phone) |> Phone.normalize_or_env()
    since = Lookback.since_from_opts(opts)

    if File.exists?(path) do
      case Sqlite.with_connection(
             path,
             fn conn ->
               tables = Sqlite.list_tables(conn)

               cond do
                 "ZCALLRECORD" in tables ->
                   query_zcallrecord(conn, limit, my_phone, since)

                 "call" in tables ->
                   query_call_table(conn, limit, my_phone, since)

                 true ->
                   {:error,
                    "Unexpected Call History schema in #{path}. Tables: #{inspect(tables)}. Adjust lib/dnc_watchdog/enforcement/local/call_history.ex"}
               end
             end,
             prefer_live: true
           ) do
        {:error, {:database_open_failed, reason}} ->
          {:error,
           "Could not open Call History DB (permission/encryption/lock?). Details: #{inspect(reason)}"}

        other ->
          other
      end
    else
      {:error,
       "Call History database not found at #{path}. Grant Full Disk Access to Terminal/Cursor. On some macOS versions this database is encrypted."}
    end
  end

  defp query_zcallrecord(conn, limit, my_phone, since) do
    where_clause = Lookback.calls_where_fragment(since, "ZDATE")

    sql = """
    SELECT
      ZDATE,
      ZDURATION,
      ZORIGINATED,
      CAST(ZADDRESS AS TEXT) AS address,
      ZNAME
    FROM ZCALLRECORD
    #{where_clause}
    ORDER BY ZDATE DESC
    #{Lookback.sql_limit_clause(since, limit)}
    """

    case Sqlite.query_rows(conn, sql) do
      {:ok, rows} -> {:ok, Enum.map(rows, &zcall_row(&1, my_phone))}
      {:error, reason} -> {:error, "Call history query failed: #{inspect(reason)}"}
    end
  end

  defp query_call_table(conn, limit, my_phone, since) do
    {:ok, columns} = Sqlite.table_columns(conn, "call")

    date_col = pick(columns, ["ZDATE", "date", "timestamp"])
    duration_col = pick(columns, ["ZDURATION", "duration"])
    originated_col = pick(columns, ["ZORIGINATED", "originated", "is_outgoing"])
    address_col = pick(columns, ["ZADDRESS", "address", "phone_number", "remote_handle"])

    if date_col && address_col do
      duration_sql = if duration_col, do: duration_col, else: "0"
      originated_sql = if originated_col, do: originated_col, else: "0"

      sql = """
      SELECT
        #{date_col},
        #{duration_sql},
        #{originated_sql},
        CAST(#{address_col} AS TEXT),
        NULL
      FROM call
      #{Lookback.calls_where_fragment(since, date_col)}
      ORDER BY #{date_col} DESC
      #{Lookback.sql_limit_clause(since, limit)}
      """

      case Sqlite.query_rows(conn, sql) do
        {:ok, rows} -> {:ok, Enum.map(rows, &zcall_row(&1, my_phone))}
        {:error, reason} -> {:error, "Call history query failed: #{inspect(reason)}"}
      end
    else
      {:error, "Could not map `call` table columns: #{inspect(columns)}"}
    end
  end

  defp zcall_row([apple_date, duration, originated, address, name], my_phone) do
    originated? = originated in [1, "1", true]
    peer = Phone.normalize(address)
    my = Phone.normalize(my_phone)

    {direction, from_number, to_number} =
      if originated? do
        {"outgoing", my, peer}
      else
        {"incoming", peer, my}
      end

    company =
      name
      |> Sqlite.cell_to_string()
      |> String.trim()
      |> case do
        "" -> ""
        value -> value
      end

    %{
      timestamp: apple_timestamp_to_naive(apple_date),
      channel: "call",
      direction: direction,
      from_number: from_number,
      to_number: to_number,
      duration_seconds: duration_to_seconds(duration),
      body: "",
      company: company
    }
  end

  defp pick(columns, candidates) do
    Enum.find(candidates, fn candidate ->
      Enum.any?(columns, &(String.downcase(&1) == String.downcase(candidate)))
    end)
    |> case do
      nil -> nil
      name -> Enum.find(columns, &(String.downcase(&1) == String.downcase(name)))
    end
  end

  defp duration_to_seconds(value) when is_integer(value), do: value
  defp duration_to_seconds(value) when is_float(value), do: trunc(value)

  defp duration_to_seconds(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> trunc(num)
      :error -> 0
    end
  end

  defp duration_to_seconds(_), do: 0

  defp apple_timestamp_to_naive(value) when is_integer(value) do
    seconds = value + @apple_epoch_seconds
    DateTime.from_unix!(seconds, :second) |> DateTime.to_naive()
  end

  defp apple_timestamp_to_naive(value) when is_float(value),
    do: apple_timestamp_to_naive(trunc(value))

  defp apple_timestamp_to_naive(_), do: ~N[1970-01-01 00:00:00]
end

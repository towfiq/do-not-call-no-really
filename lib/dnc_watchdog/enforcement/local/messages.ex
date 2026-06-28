defmodule DncWatchdog.Enforcement.Local.Messages do
  @moduledoc """
  Reads SMS/iMessage rows from macOS Messages `chat.db`.
  """

  alias DncWatchdog.Enforcement.Local.AttributedBody
  alias DncWatchdog.Enforcement.Local.Lookback
  alias DncWatchdog.Enforcement.Phone
  alias DncWatchdog.Enforcement.Sqlite

  @apple_epoch_seconds 978_307_200

  def read(path, opts \\ []) do
    limit = Keyword.get(opts, :limit)
    my_phone = opts |> Keyword.get(:my_phone) |> Phone.normalize_or_env()
    since = Lookback.since_from_opts(opts)

    if File.exists?(path) do
      case Sqlite.with_connection(path, fn conn ->
             tables = Sqlite.list_tables(conn)

             if "message" in tables do
               schema = schema_flags(conn, tables)
               sql = messages_sql(schema, limit, since)

               case Sqlite.query_rows(conn, sql) do
                 {:ok, rows} ->
                   rows =
                     rows
                     |> Enum.map(&to_row(&1, my_phone))
                     |> Enum.reject(&(&1.body == ""))

                   {:ok, rows}

                 {:error, reason} ->
                   {:error, "Messages query failed: #{inspect(reason)}"}
               end
             else
               {:error, "Unexpected Messages schema in #{path}. Tables: #{inspect(tables)}"}
             end
           end) do
        {:error, {:database_open_failed, reason}} ->
          {:error,
           "Could not open Messages DB (permission/lock?). Grant Full Disk Access. Details: #{inspect(reason)}"}

        other ->
          other
      end
    else
      {:error,
       "Messages database not found at #{path}. Grant Full Disk Access to Terminal/Cursor in System Settings → Privacy & Security."}
    end
  end

  @doc """
  Searches `chat.db` for rows matching a phone fragment (for diagnostics).
  """
  def search(path, phone_fragment, opts \\ []) when is_binary(phone_fragment) do
    limit = Keyword.get(opts, :limit, 20)
    digits = Phone.normalize(phone_fragment)

    if digits == "" do
      {:error, "Provide a phone number fragment to search"}
    else
      like = "%#{digits}%"

      if File.exists?(path) do
        Sqlite.with_connection(path, fn conn ->
          tables = Sqlite.list_tables(conn)

          if "message" in tables do
            schema = schema_flags(conn, tables)
            sql = search_sql(schema, like, limit)

            case Sqlite.query_rows(conn, sql) do
              {:ok, rows} -> {:ok, Enum.map(rows, &search_hit/1)}
              {:error, reason} -> {:error, "Messages search failed: #{inspect(reason)}"}
            end
          else
            {:error, "Unexpected Messages schema in #{path}"}
          end
        end)
      else
        {:error, "Messages database not found at #{path}"}
      end
    end
  end

  defp schema_flags(conn, tables) do
    %{
      handle: "handle" in tables,
      chat: "chat" in tables,
      chat_message_join: "chat_message_join" in tables,
      attributed_body: attributed_body_column?(conn)
    }
  end

  defp attributed_body_column?(conn) do
    case Sqlite.table_columns(conn, "message") do
      {:ok, columns} -> "attributedBody" in columns
      _ -> false
    end
  end

  defp messages_sql(schema, limit, since) do
    lookback = Lookback.messages_where_fragment(since)

    """
    SELECT
      m.date AS apple_date,
      m.text AS body,
      #{attributed_body_select(schema)} AS attributed_body,
      m.is_from_me AS is_from_me,
      #{peer_select(schema)} AS handle
    FROM message m
    #{from_joins(schema)}
    WHERE #{body_where(schema)}
    #{lookback}
    ORDER BY m.date DESC
    #{Lookback.sql_limit_clause(since, limit)}
    """
  end

  defp search_sql(schema, like, limit) do
    """
    SELECT
      m.ROWID AS rowid,
      m.date AS apple_date,
      m.text AS body,
      #{attributed_body_select(schema)} AS attributed_body,
      m.is_from_me AS is_from_me,
      h.id AS handle_id,
      c.chat_identifier AS chat_identifier
    FROM message m
    #{from_joins(schema)}
    WHERE (
      COALESCE(h.id, c.chat_identifier, '') LIKE '#{like}'
    )
    ORDER BY m.date DESC
    LIMIT #{limit}
    """
  end

  defp from_joins(%{handle: true} = schema) do
    joins =
      [
        "LEFT JOIN handle h ON m.handle_id = h.ROWID",
        chat_joins(schema)
      ]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n    ")

    joins
  end

  defp from_joins(_schema), do: ""

  defp chat_joins(%{chat: true, chat_message_join: true}) do
    """
    LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
    LEFT JOIN chat c ON c.ROWID = cmj.chat_id
    """
    |> String.trim()
  end

  defp chat_joins(_), do: ""

  defp peer_select(%{handle: true, chat: true, chat_message_join: true}) do
    "COALESCE(NULLIF(TRIM(h.id), ''), NULLIF(TRIM(c.chat_identifier), ''))"
  end

  defp peer_select(%{handle: true}), do: "h.id"
  defp peer_select(_), do: "NULL"

  defp attributed_body_select(%{attributed_body: true}), do: "m.attributedBody"
  defp attributed_body_select(_), do: "NULL"

  defp body_where(%{attributed_body: true}) do
    """
    (
      (m.text IS NOT NULL AND m.text != '')
      OR (m.attributedBody IS NOT NULL AND length(m.attributedBody) > 0)
    )
    """
    |> String.trim()
  end

  defp body_where(_), do: "m.text IS NOT NULL AND m.text != ''"

  defp search_hit([rowid, apple_date, body, attributed_body, is_from_me, handle_id, chat_identifier]) do
    decoded = resolve_body(body, attributed_body)

    %{
      rowid: rowid,
      timestamp: apple_timestamp_to_naive(apple_date),
      handle_id: Sqlite.cell_to_string(handle_id),
      chat_identifier: Sqlite.cell_to_string(chat_identifier),
      is_from_me: is_from_me in [1, "1", true],
      text_length: String.length(Sqlite.cell_to_string(body)),
      attributed_body_length: if(is_binary(attributed_body), do: byte_size(attributed_body), else: 0),
      decoded_body: decoded
    }
  end

  defp to_row([apple_date, body, attributed_body, is_from_me, handle], my_phone) do
    from_me? = is_from_me in [1, "1", true]
    peer = Phone.normalize(handle)
    my = Phone.normalize(my_phone)

    {direction, from_number, to_number} =
      if from_me? do
        {"outgoing", my, peer}
      else
        {"incoming", peer, my}
      end

    %{
      timestamp: apple_timestamp_to_naive(apple_date),
      channel: "sms",
      direction: direction,
      from_number: from_number,
      to_number: to_number,
      duration_seconds: 0,
      body: resolve_body(body, attributed_body),
      company: ""
    }
  end

  defp resolve_body(body, attributed_body) do
    text = body |> Sqlite.cell_to_string() |> String.trim()

    cond do
      text != "" ->
        text

      is_binary(attributed_body) and attributed_body != "" ->
        AttributedBody.extract_text(attributed_body) || ""

      true ->
        ""
    end
  end

  defp apple_timestamp_to_naive(value) when is_integer(value) do
    seconds =
      if value > 1_000_000_000_000,
        do: div(value, 1_000_000_000) + @apple_epoch_seconds,
        else: value + @apple_epoch_seconds

    DateTime.from_unix!(seconds, :second) |> DateTime.to_naive()
  end

  defp apple_timestamp_to_naive(value) when is_float(value),
    do: apple_timestamp_to_naive(trunc(value))

  defp apple_timestamp_to_naive(_), do: ~N[1970-01-01 00:00:00]
end

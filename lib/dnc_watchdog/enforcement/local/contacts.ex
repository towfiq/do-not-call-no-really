defmodule DncWatchdog.Enforcement.Local.Contacts do
  @moduledoc """
  Loads phone numbers, emails, and display names from macOS Address Book SQLite databases.

  Contacts whose organization/company name contains "dnc" (case-insensitive) are
  omitted from the phone and email sets so their communications stay eligible
  for import. Their display names are still returned so sync can label those rows.
  """

  alias DncWatchdog.Enforcement.ContactFilter
  alias DncWatchdog.Enforcement.Local.Paths
  alias DncWatchdog.Enforcement.Phone
  alias DncWatchdog.Enforcement.Sqlite

  def load(opts \\ []) do
    paths = Keyword.get(opts, :contacts_dbs) || Paths.contacts_dbs()

    if paths == [] do
      {:ok, ContactFilter.empty_set(), []}
    else
      {phones, emails, names, loaded_paths, errors} =
        Enum.reduce(paths, {MapSet.new(), MapSet.new(), %{}, [], []}, fn path,
                                                                         {phones, emails, names,
                                                                          loaded, errors} ->
          case read_path(path) do
            {:ok, path_phones, path_emails, path_names} ->
              {MapSet.union(phones, path_phones), MapSet.union(emails, path_emails),
               merge_names(names, path_names), [path | loaded], errors}

            {:error, reason} ->
              {phones, emails, names, loaded, [{path, reason} | errors]}
          end
        end)

      set = %{phones: phones, emails: emails, names: names}

      if MapSet.size(phones) == 0 and MapSet.size(emails) == 0 and errors != [] do
        {:error, {:contacts_unreadable, errors}}
      else
        {:ok, set, Enum.reverse(loaded_paths)}
      end
    end
  end

  defp read_path(path) do
    Sqlite.with_connection(path, fn conn ->
      tables = Sqlite.list_tables(conn) |> MapSet.new()

      phones =
        phone_queries(tables)
        |> Enum.flat_map(fn sql -> query_phone_rows(conn, sql, tables) end)
        |> Enum.flat_map(&phone_lookup_keys/1)
        |> Enum.reject(&(&1 == ""))
        |> MapSet.new()

      emails =
        email_queries(tables)
        |> Enum.flat_map(fn sql -> query_values(conn, sql, tables) end)
        |> Enum.map(&String.downcase/1)
        |> Enum.reject(&(&1 == ""))
        |> MapSet.new()

      names = read_names(conn, tables)
      {phones, emails, names}
    end)
    |> case do
      {:error, _} = error ->
        error

      {phones, emails, names} ->
        {:ok, phones, emails, names}
    end
  end

  defp merge_names(left, right) do
    Map.merge(left, right, fn _key, existing, _new -> existing end)
  end

  defp read_names(conn, tables) do
    %{}
    |> put_named_rows(conn, phone_name_sqls(conn, tables), &put_phone_name/2)
    |> put_named_rows(conn, email_name_sqls(conn, tables), &put_email_name/2)
  end

  defp put_named_rows(names, conn, sqls, reducer) do
    Enum.reduce(sqls, names, fn sql, acc ->
      case Sqlite.query_rows(conn, sql) do
        {:ok, rows} -> Enum.reduce(rows, acc, reducer)
        {:error, _} -> acc
      end
    end)
  end

  defp put_phone_name(row, names) when is_list(row) and length(row) >= 8 do
    name = display_name(Enum.slice(row, 4, 4))

    if name == "" do
      names
    else
      row
      |> Enum.take(4)
      |> phone_lookup_keys()
      |> Enum.reduce(names, fn key, acc -> Map.put_new(acc, key, name) end)
    end
  end

  defp put_phone_name(_row, names), do: names

  defp put_email_name(row, names) when is_list(row) and length(row) >= 5 do
    email = row |> hd() |> Sqlite.cell_to_string() |> String.trim() |> String.downcase()
    name = display_name(Enum.slice(row, 1, 4))

    if email == "" or name == "" do
      names
    else
      Map.put_new(names, email, name)
    end
  end

  defp put_email_name(_row, names), do: names

  defp display_name(cells) do
    [zname, first, last, org] = Enum.map(cells, &clean_cell/1)

    person =
      [first, last]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    cond do
      person != "" -> person
      org != "" -> org
      true -> zname
    end
  end

  defp clean_cell(value) do
    value |> Sqlite.cell_to_string() |> String.trim()
  end

  defp phone_name_sqls(conn, tables) do
    [
      if(MapSet.member?(tables, "ZABCDRECORD") and MapSet.member?(tables, "ZABCDPHONENUMBER"),
        do: modern_phone_name_sql(conn)
      ),
      if(MapSet.member?(tables, "ABPerson") and MapSet.member?(tables, "ABPersonPhoneNumber"),
        do: legacy_phone_name_sql(conn)
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp email_name_sqls(conn, tables) do
    [
      if(MapSet.member?(tables, "ZABCDRECORD") and MapSet.member?(tables, "ZABCDEMAILADDRESS"),
        do: modern_email_name_sql(conn)
      ),
      if(MapSet.member?(tables, "ABPerson") and MapSet.member?(tables, "ABPersonEmail"),
        do: legacy_email_name_sql(conn)
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp modern_phone_name_sql(conn) do
    with {:ok, phone_cols} <- Sqlite.table_columns(conn, "ZABCDPHONENUMBER"),
         {:ok, record_cols} <- Sqlite.table_columns(conn, "ZABCDRECORD") do
      phone_cols = MapSet.new(phone_cols)
      record_cols = MapSet.new(record_cols)

      """
      SELECT
        #{column_expr(phone_cols, ["ZFULLNUMBER"], "p")},
        #{column_expr(phone_cols, ["ZAREACODE"], "p")},
        #{column_expr(phone_cols, ["ZLOCALNUMBER"], "p")},
        #{column_expr(phone_cols, ["ZCOUNTRYCODE"], "p")},
        #{column_expr(record_cols, ["ZNAME"], "r")},
        #{column_expr(record_cols, ["ZFIRSTNAME", "Z22_FIRSTNAME"], "r")},
        #{column_expr(record_cols, ["ZLASTNAME", "Z22_LASTNAME"], "r")},
        #{column_expr(record_cols, ["ZORGANIZATION", "Z22_ORGANIZATION"], "r")}
      FROM ZABCDPHONENUMBER p
      LEFT JOIN ZABCDRECORD r ON p.ZOWNER = r.Z_PK
      WHERE #{column_expr(phone_cols, ["ZFULLNUMBER"], "p")} IS NOT NULL
         OR #{column_expr(phone_cols, ["ZLOCALNUMBER"], "p")} IS NOT NULL
      """
    else
      _ -> nil
    end
  end

  defp modern_email_name_sql(conn) do
    with {:ok, email_cols} <- Sqlite.table_columns(conn, "ZABCDEMAILADDRESS"),
         {:ok, record_cols} <- Sqlite.table_columns(conn, "ZABCDRECORD") do
      email_cols = MapSet.new(email_cols)
      record_cols = MapSet.new(record_cols)

      """
      SELECT
        #{column_expr(email_cols, ["ZADDRESS"], "e")},
        #{column_expr(record_cols, ["ZNAME"], "r")},
        #{column_expr(record_cols, ["ZFIRSTNAME", "Z22_FIRSTNAME"], "r")},
        #{column_expr(record_cols, ["ZLASTNAME", "Z22_LASTNAME"], "r")},
        #{column_expr(record_cols, ["ZORGANIZATION", "Z22_ORGANIZATION"], "r")}
      FROM ZABCDEMAILADDRESS e
      LEFT JOIN ZABCDRECORD r ON e.ZOWNER = r.Z_PK
      WHERE #{column_expr(email_cols, ["ZADDRESS"], "e")} IS NOT NULL
      """
    else
      _ -> nil
    end
  end

  defp legacy_phone_name_sql(conn) do
    case Sqlite.table_columns(conn, "ABPerson") do
      {:ok, columns} ->
        columns = MapSet.new(columns)

        """
        SELECT
          p.value,
          NULL,
          NULL,
          NULL,
          #{column_expr(columns, ["Name"], "person")},
          #{column_expr(columns, ["First", "FirstName"], "person")},
          #{column_expr(columns, ["Last", "LastName"], "person")},
          #{column_expr(columns, ["Organization"], "person")}
        FROM ABPersonPhoneNumber p
        LEFT JOIN ABPerson person ON p.UID = person.ROWID
        WHERE p.value IS NOT NULL
        """

      _ ->
        nil
    end
  end

  defp legacy_email_name_sql(conn) do
    case Sqlite.table_columns(conn, "ABPerson") do
      {:ok, columns} ->
        columns = MapSet.new(columns)

        """
        SELECT
          e.value,
          #{column_expr(columns, ["Name"], "person")},
          #{column_expr(columns, ["First", "FirstName"], "person")},
          #{column_expr(columns, ["Last", "LastName"], "person")},
          #{column_expr(columns, ["Organization"], "person")}
        FROM ABPersonEmail e
        LEFT JOIN ABPerson person ON e.UID = person.ROWID
        WHERE e.value IS NOT NULL
        """

      _ ->
        nil
    end
  end

  defp column_expr(columns, candidates, qualifier) do
    case Enum.find(candidates, &MapSet.member?(columns, &1)) do
      nil -> "NULL"
      column -> "#{qualifier}.#{column}"
    end
  end

  defp query_phone_rows(conn, sql, tables) do
    case table_from_sql(sql) do
      nil ->
        []

      table ->
        if MapSet.member?(tables, table) do
          case Sqlite.query_rows(conn, sql) do
            {:ok, rows} -> rows
            {:error, _} -> []
          end
        else
          []
        end
    end
  end

  defp query_values(conn, sql, tables) do
    case table_from_sql(sql) do
      nil ->
        []

      table ->
        if MapSet.member?(tables, table) do
          case Sqlite.query_rows(conn, sql) do
            {:ok, rows} -> Enum.map(rows, fn [value] -> Sqlite.cell_to_string(value) end)
            {:error, _} -> []
          end
        else
          []
        end
    end
  end

  defp phone_lookup_keys([value]) when not is_list(value) do
    value |> Sqlite.cell_to_string() |> Phone.lookup_keys()
  end

  defp phone_lookup_keys([full, area, local, country]) do
    full = full |> Sqlite.cell_to_string() |> String.trim()

    if full != "" do
      Phone.lookup_keys(full)
    else
      area = area |> Sqlite.cell_to_string() |> Phone.normalize()
      local = local |> Sqlite.cell_to_string() |> Phone.normalize()
      country = country |> Sqlite.cell_to_string() |> Phone.normalize()

      composed =
        cond do
          area != "" and local != "" -> area <> local
          local != "" -> local
          true -> ""
        end

      if composed == "" do
        []
      else
        digits =
          if country != "" and byte_size(composed) <= 10 and
               not String.starts_with?(composed, country) do
            country <> composed
          else
            composed
          end

        Phone.lookup_keys(digits)
      end
    end
  end

  defp phone_lookup_keys(row),
    do: row |> List.first() |> Sqlite.cell_to_string() |> Phone.lookup_keys()

  defp table_from_sql(sql) do
    case Regex.run(~r/\bFROM\s+([A-Za-z0-9_]+)/i, sql) do
      [_, table] -> table
      _ -> nil
    end
  end

  defp phone_queries(tables) do
    modern =
      if MapSet.member?(tables, "ZABCDRECORD") do
        """
        SELECT p.ZFULLNUMBER, p.ZAREACODE, p.ZLOCALNUMBER, p.ZCOUNTRYCODE
        FROM ZABCDPHONENUMBER p
        LEFT JOIN ZABCDRECORD r ON p.ZOWNER = r.Z_PK
        WHERE (p.ZFULLNUMBER IS NOT NULL OR p.ZLOCALNUMBER IS NOT NULL)
          AND NOT (#{dnc_organization_sql("r.ZORGANIZATION")})
        """
      else
        """
        SELECT ZFULLNUMBER, ZAREACODE, ZLOCALNUMBER, ZCOUNTRYCODE
        FROM ZABCDPHONENUMBER
        WHERE ZFULLNUMBER IS NOT NULL OR ZLOCALNUMBER IS NOT NULL
        """
      end

    legacy =
      if MapSet.member?(tables, "ABPerson") do
        """
        SELECT p.value
        FROM ABPersonPhoneNumber p
        LEFT JOIN ABPerson person ON p.UID = person.ROWID
        WHERE p.value IS NOT NULL
          AND NOT (#{dnc_organization_sql("person.Organization")})
        """
      else
        "SELECT value FROM ABPersonPhoneNumber WHERE value IS NOT NULL"
      end

    [modern, legacy]
  end

  defp email_queries(tables) do
    modern =
      if MapSet.member?(tables, "ZABCDRECORD") do
        """
        SELECT e.ZADDRESS
        FROM ZABCDEMAILADDRESS e
        LEFT JOIN ZABCDRECORD r ON e.ZOWNER = r.Z_PK
        WHERE e.ZADDRESS IS NOT NULL
          AND NOT (#{dnc_organization_sql("r.ZORGANIZATION")})
        """
      else
        "SELECT ZADDRESS FROM ZABCDEMAILADDRESS WHERE ZADDRESS IS NOT NULL"
      end

    legacy =
      if MapSet.member?(tables, "ABPerson") do
        """
        SELECT e.value
        FROM ABPersonEmail e
        LEFT JOIN ABPerson person ON e.UID = person.ROWID
        WHERE e.value IS NOT NULL
          AND NOT (#{dnc_organization_sql("person.Organization")})
        """
      else
        "SELECT value FROM ABPersonEmail WHERE value IS NOT NULL"
      end

    [modern, legacy]
  end

  defp dnc_organization_sql(column) do
    "instr(lower(coalesce(#{column}, '')), 'dnc') > 0"
  end
end

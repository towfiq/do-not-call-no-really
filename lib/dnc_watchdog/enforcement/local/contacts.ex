defmodule DncWatchdog.Enforcement.Local.Contacts do
  @moduledoc """
  Loads phone numbers and emails from macOS Address Book SQLite databases.

  Contacts whose organization/company name contains "dnc" (case-insensitive) are
  omitted from the set so their communications stay eligible for import.
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
      {phones, emails, loaded_paths, errors} =
        Enum.reduce(paths, {MapSet.new(), MapSet.new(), [], []}, fn path, acc ->
          case read_path(path) do
            {:ok, path_phones, path_emails} ->
              {MapSet.union(elem(acc, 0), path_phones), MapSet.union(elem(acc, 1), path_emails),
               [path | elem(acc, 2)], elem(acc, 3)}

            {:error, reason} ->
              {elem(acc, 0), elem(acc, 1), elem(acc, 2), [{path, reason} | elem(acc, 3)]}
          end
        end)

      set = %{phones: phones, emails: emails}

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

      {phones, emails}
    end)
    |> case do
      {:error, _} = error ->
        error

      {phones, emails} ->
        {:ok, phones, emails}
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

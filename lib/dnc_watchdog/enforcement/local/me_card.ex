defmodule DncWatchdog.Enforcement.Local.MeCard do
  @moduledoc """
  Reads the macOS Contacts "Me" card (name, mailing address, phone, email).
  """

  alias DncWatchdog.Enforcement.Local.Paths
  alias DncWatchdog.Enforcement.Phone
  alias DncWatchdog.Enforcement.Sqlite

  @type t :: %{
          optional(:name) => String.t(),
          optional(:address) => String.t(),
          optional(:phone) => String.t(),
          optional(:email) => String.t()
        }

  @doc """
  Reads the Me card from the first readable Contacts database.

  Returns `{:ok, map}` with any fields found, `{:error, :not_found}` when no Me
  card exists, or `{:error, {:contacts_unreadable, errors}}` when databases
  cannot be opened (often missing Full Disk Access).
  """
  @spec read(keyword()) :: {:ok, t()} | {:error, :not_found | {:contacts_unreadable, list()}}
  def read(opts \\ []) do
    paths = Keyword.get(opts, :contacts_dbs) || Paths.contacts_dbs()

    if paths == [] do
      {:error, :not_found}
    else
      read_paths(paths, [])
    end
  end

  defp read_paths([], errors) do
    if errors == [] do
      {:error, :not_found}
    else
      {:error, {:contacts_unreadable, Enum.reverse(errors)}}
    end
  end

  defp read_paths([path | rest], errors) do
    case read_path(path) do
      {:ok, card} when map_size(card) > 0 ->
        {:ok, card}

      {:ok, _} ->
        read_paths(rest, errors)

      {:error, reason} ->
        read_paths(rest, [{path, reason} | errors])
    end
  end

  defp read_path(path) do
    Sqlite.with_connection(path, fn conn ->
      tables = Sqlite.list_tables(conn) |> MapSet.new()

      if MapSet.member?(tables, "ZABCDRECORD") do
        case me_record_pk(conn) do
          {:ok, pk} ->
            card =
              %{
                name: read_name(conn, pk),
                address: read_address(conn, tables, pk),
                phone: read_phone(conn, tables, pk),
                email: read_email(conn, tables, pk)
              }
              |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
              |> Map.new()

            {:ok, card}

          _ ->
            {:ok, %{}}
        end
      else
        {:ok, %{}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      other -> other
    end
  end

  defp me_record_pk(conn) do
    me_queries = [
      "SELECT Z_PK FROM ZABCDRECORD WHERE ZME = 1 LIMIT 1",
      "SELECT Z_PK FROM ZABCDRECORD WHERE Z22_ME = 1 LIMIT 1"
    ]

    Enum.find_value(me_queries, fn sql ->
      case Sqlite.query_rows(conn, sql) do
        {:ok, [[pk]]} when is_integer(pk) -> {:ok, pk}
        _ -> nil
      end
    end) || {:error, :no_me_record}
  end

  defp read_name(conn, pk) do
    sql = """
    SELECT ZNAME, ZFIRSTNAME, ZLASTNAME, ZORGANIZATION
    FROM ZABCDRECORD
    WHERE Z_PK = #{pk}
    LIMIT 1
    """

    case Sqlite.query_rows(conn, sql) do
      {:ok, [[zname, first, last, org]]} ->
        [zname, compose_name(first, last), org]
        |> Enum.map(&Sqlite.cell_to_string/1)
        |> Enum.find_value(&present/1)

      _ ->
        nil
    end
  end

  defp compose_name(first, last) do
    [first, last]
    |> Enum.map(&Sqlite.cell_to_string/1)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
    |> case do
      "" -> nil
      name -> name
    end
  end

  defp read_address(conn, tables, pk) do
    if MapSet.member?(tables, "ZABCDPOSTALADDRESS") do
      sql = """
      SELECT ZSTREET, ZCITY, ZSTATE, ZZIPCODE
      FROM ZABCDPOSTALADDRESS
      WHERE ZOWNER = #{pk}
      ORDER BY COALESCE(ZISPRIMARY, 0) DESC, COALESCE(ZORDERINGINDEX, 0) ASC
      LIMIT 1
      """

      case Sqlite.query_rows(conn, sql) do
        {:ok, [[street, city, state, zip]]} ->
          format_postal(street, city, state, zip)

        _ ->
          nil
      end
    end
  end

  defp read_phone(conn, tables, pk) do
    if MapSet.member?(tables, "ZABCDPHONENUMBER") do
      sql = """
      SELECT ZFULLNUMBER
      FROM ZABCDPHONENUMBER
      WHERE ZFULLNUMBER IS NOT NULL AND ZOWNER = #{pk}
      ORDER BY COALESCE(ZISPRIMARY, 0) DESC, COALESCE(ZORDERINGINDEX, 0) ASC
      LIMIT 1
      """

      case Sqlite.query_rows(conn, sql) do
        {:ok, [[number]]} ->
          number |> Sqlite.cell_to_string() |> Phone.normalize() |> present()

        _ ->
          nil
      end
    end
  end

  defp read_email(conn, tables, pk) do
    if MapSet.member?(tables, "ZABCDEMAILADDRESS") do
      sql = """
      SELECT ZADDRESS
      FROM ZABCDEMAILADDRESS
      WHERE ZADDRESS IS NOT NULL AND ZOWNER = #{pk}
      ORDER BY COALESCE(ZISPRIMARY, 0) DESC, COALESCE(ZORDERINGINDEX, 0) ASC
      LIMIT 1
      """

      case Sqlite.query_rows(conn, sql) do
        {:ok, [[email]]} ->
          email |> Sqlite.cell_to_string() |> present()

        _ ->
          nil
      end
    end
  end

  defp format_postal(street, city, state, zip) do
    street = street |> Sqlite.cell_to_string() |> present()
    city = city |> Sqlite.cell_to_string() |> present()
    state = state |> Sqlite.cell_to_string() |> present()
    zip = zip |> Sqlite.cell_to_string() |> present()

    city_line = city_state_zip(city, state, zip)

    [street, city_line]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
    |> present()
  end

  defp city_state_zip(city, state, zip) do
    cond do
      has_value?(city) and has_value?(state) and has_value?(zip) ->
        "#{city}, #{state} #{zip}"

      has_value?(city) and has_value?(state) ->
        "#{city}, #{state}"

      true ->
        [city, state, zip]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(", ")
        |> present()
    end
  end

  defp has_value?(value), do: value not in [nil, ""]

  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value
end

defmodule DncWatchdog.Enforcement.PostgresImporter do
  @moduledoc """
  One-time copy of application data from PostgreSQL into the local SQLite repo.
  """

  alias DncWatchdog.Repo

  @tables ~w(
    legal_entities
    claimant_profiles
    excluded_senders
    cases
    communications
    evidence_attachments
  )

  @datetime_fields ~w(inserted_at updated_at mail_tracking_checked_at)
  @naive_datetime_fields ~w(timestamp)
  @date_fields ~w(dnc_registration_date stop_contact_date)
  @decimal_fields ~w(relief_amount_per_violation settlement_amount)
  @integer_fields ~w(id case_id legal_entity_id communication_id duration_seconds)
  @boolean_fields ~w(spam)

  @type summary :: %{
          tables: %{String.t() => non_neg_integer()},
          total_rows: non_neg_integer()
        }

  @doc """
  Copies all application tables from PostgreSQL into SQLite, preserving primary keys
  and foreign keys. Existing SQLite rows in those tables are removed first.
  """
  @spec import_all(keyword()) :: summary()
  def import_all(opts \\ []) do
    pg = Keyword.get(opts, :postgres, default_postgres_config())
    batch_size = Keyword.get(opts, :batch_size, 500)

    exported =
      Enum.reduce(@tables, %{}, fn table, acc ->
        Map.put(acc, table, fetch_rows(pg, table))
      end)

    schema_migrations = fetch_schema_migrations(pg)

    Repo.transaction(fn ->
      Ecto.Adapters.SQL.query!(Repo, "PRAGMA foreign_keys = OFF")

      Enum.each(Enum.reverse(@tables), fn table ->
        Ecto.Adapters.SQL.query!(Repo, "DELETE FROM #{table}")
      end)

      counts =
        Enum.reduce(@tables, %{}, fn table, acc ->
          rows = Map.fetch!(exported, table)
          insert_rows(table, rows, batch_size)
          Map.put(acc, table, length(rows))
        end)

      replace_schema_migrations(schema_migrations)
      Ecto.Adapters.SQL.query!(Repo, "PRAGMA foreign_keys = ON")

      total_rows = counts |> Map.values() |> Enum.sum()
      %{tables: counts, total_rows: total_rows}
    end)
    |> case do
      {:ok, summary} -> summary
      {:error, reason} -> raise "SQLite import failed: #{inspect(reason)}"
    end
  end

  defp fetch_rows(pg, table) do
    sql = """
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::json)
    FROM (SELECT * FROM #{table} ORDER BY id) t
    """

    pg
    |> psql!(sql)
    |> Jason.decode!()
    |> Enum.map(&coerce_row/1)
  end

  defp fetch_schema_migrations(pg) do
    sql = """
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::json)
    FROM (SELECT version, inserted_at FROM schema_migrations ORDER BY version) t
    """

    pg
    |> psql!(sql)
    |> Jason.decode!()
    |> Enum.map(fn row ->
      %{
        version: coerce_integer(row["version"]),
        inserted_at: coerce_naive_datetime(row["inserted_at"])
      }
    end)
  end

  defp coerce_row(row) when is_map(row) do
    Map.new(row, fn {key, value} -> {String.to_atom(key), coerce_field(key, value)} end)
  end

  defp coerce_field(_key, nil), do: nil

  defp coerce_field(key, value) when key in @boolean_fields, do: coerce_boolean(value)
  defp coerce_field(key, value) when key in @integer_fields, do: coerce_integer(value)
  defp coerce_field(key, value) when key in @datetime_fields, do: coerce_datetime(value)

  defp coerce_field(key, value) when key in @naive_datetime_fields,
    do: coerce_naive_datetime(value)

  defp coerce_field(key, value) when key in @date_fields, do: coerce_date(value)
  defp coerce_field(key, value) when key in @decimal_fields, do: coerce_decimal(value)
  defp coerce_field(_key, value), do: value

  defp coerce_boolean(true), do: 1
  defp coerce_boolean(false), do: 0
  defp coerce_boolean("true"), do: 1
  defp coerce_boolean("false"), do: 0
  defp coerce_boolean("TRUE"), do: 1
  defp coerce_boolean("FALSE"), do: 0
  defp coerce_boolean(1), do: 1
  defp coerce_boolean(0), do: 0
  defp coerce_boolean(_), do: 0

  defp coerce_integer(value) when is_integer(value), do: value

  defp coerce_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> value
    end
  end

  defp coerce_integer(value), do: value

  defp coerce_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(normalize_pg_timestamp(value)) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> parse_naive_as_utc(value)
    end
  end

  defp coerce_datetime(%DateTime{} = value), do: DateTime.truncate(value, :second)

  defp coerce_naive_datetime(value) when is_binary(value) do
    value
    |> normalize_pg_timestamp()
    |> NaiveDateTime.from_iso8601!()
    |> NaiveDateTime.truncate(:second)
  end

  defp coerce_naive_datetime(%NaiveDateTime{} = value), do: NaiveDateTime.truncate(value, :second)

  defp coerce_date(value) when is_binary(value), do: Date.from_iso8601!(value)
  defp coerce_date(%Date{} = value), do: value

  defp coerce_decimal(value) when is_binary(value), do: Decimal.new(value)
  defp coerce_decimal(value) when is_number(value), do: Decimal.new(to_string(value))
  defp coerce_decimal(%Decimal{} = value), do: value

  defp parse_naive_as_utc(value) do
    value
    |> normalize_pg_timestamp()
    |> NaiveDateTime.from_iso8601!()
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.truncate(:second)
  end

  defp normalize_pg_timestamp(value) do
    value
    |> String.replace(" ", "T")
    |> String.replace_suffix("+00", "Z")
  end

  defp insert_rows(_table, [], _batch_size), do: :ok

  defp insert_rows(table, rows, batch_size) do
    rows
    |> Enum.chunk_every(batch_size)
    |> Enum.each(fn chunk ->
      {count, _} = Repo.insert_all(table, chunk)

      if count != length(chunk) do
        raise "insert_all returned #{count} for #{length(chunk)} rows in #{table}"
      end
    end)
  end

  defp replace_schema_migrations(rows) do
    Ecto.Adapters.SQL.query!(Repo, "DELETE FROM schema_migrations")
    Repo.insert_all("schema_migrations", rows)
  end

  defp psql!(pg, sql) do
    args =
      [
        "-h",
        pg[:hostname] || "localhost",
        "-U",
        pg[:username] || "postgres",
        "-d",
        pg[:database] || "dnc_watchdog_dev",
        "-t",
        "-A",
        "-c",
        sql
      ]

    env = [{"PGPASSWORD", pg[:password] || "postgres"}]

    case System.cmd("psql", args, env: env, stderr_to_stdout: true) do
      {output, 0} ->
        output |> String.trim()

      {output, status} ->
        raise "psql failed (status #{status}): #{String.trim(output)}"
    end
  end

  defp default_postgres_config do
    [
      hostname: System.get_env("PGHOST") || "localhost",
      username: System.get_env("PGUSER") || "postgres",
      password: System.get_env("PGPASSWORD") || "postgres",
      database: System.get_env("PGDATABASE") || "dnc_watchdog_dev"
    ]
  end
end

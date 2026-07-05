defmodule DncWatchdog.Enforcement.Sqlite do
  @moduledoc """
  Read-only SQLite access for local macOS databases.

  Safety guarantees for Apple system databases:

  1. Prefer copying the database (and `-wal`/`-shm` sidecars when present) to a temp file.
  2. Open copies with SQLite `mode=ro` and `immutable=1`, and enable `PRAGMA query_only = ON`.
  3. When copying fails (for example macOS "not owner" on protected Library files), fall back to
     opening the original path read-only (`immutable=1` + `query_only`) without writing to it.
  4. Temp copies are deleted when the connection closes.
  """

  def with_connection(source_path, callback) when is_function(callback, 1) do
    case snapshot_source(source_path) do
      {:ok, snapshot_path} ->
        with_readonly_connection(snapshot_path, callback,
          cleanup: snapshot_path,
          on_open_error: nil
        )

      {:error, {:source_not_found, _} = reason} ->
        {:error, reason}

      {:error, snapshot_reason} ->
        with_readonly_connection(source_path, callback,
          cleanup: nil,
          on_open_error: fn open_reason ->
            {:error, {:database_open_failed, %{snapshot: snapshot_reason, direct: open_reason}}}
          end
        )
    end
  end

  defp with_readonly_connection(path, callback, opts) do
    cleanup = Keyword.get(opts, :cleanup)
    on_open_error = Keyword.get(opts, :on_open_error)

    try do
      case open_readonly(path) do
        {:ok, conn} ->
          try do
            callback.(conn)
          after
            Exqlite.Sqlite3.close(conn)
          end

        {:error, reason} ->
          if on_open_error do
            on_open_error.(reason)
          else
            {:error, {:database_open_failed, reason}}
          end
      end
    after
      if cleanup, do: cleanup_snapshot(cleanup)
    end
  end

  def list_tables(conn) do
    case query_rows(conn, "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY 1") do
      {:ok, rows} -> Enum.map(rows, &cell_to_string(hd(&1)))
      error -> error
    end
  end

  def table_columns(conn, table) do
    sql = "PRAGMA table_info(#{table})"

    case query_rows(conn, sql) do
      {:ok, rows} -> {:ok, Enum.map(rows, fn row -> cell_to_string(Enum.at(row, 1)) end)}
      error -> error
    end
  end

  def query_rows(conn, sql) do
    with {:ok, stmt} <- Exqlite.Sqlite3.prepare(conn, sql) do
      collect_rows(conn, stmt, [])
    end
  end

  defp collect_rows(conn, stmt, acc) do
    case Exqlite.Sqlite3.multi_step(conn, stmt) do
      {:rows, rows} ->
        collect_rows(conn, stmt, acc ++ rows)

      {:done, rows} ->
        {:ok, acc ++ rows}

      :busy ->
        {:error, :busy}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def cell_to_string(nil), do: ""
  def cell_to_string(value) when is_binary(value), do: value
  def cell_to_string(value) when is_integer(value), do: Integer.to_string(value)
  def cell_to_string(value) when is_float(value), do: Float.to_string(value)
  def cell_to_string(value), do: to_string(value)

  defp open_readonly(path) do
    uri = readonly_uri(path)

    with {:ok, conn} <- Exqlite.Sqlite3.open(uri, filename: path),
         :ok <- enable_query_only!(conn) do
      {:ok, conn}
    end
  end

  defp readonly_uri(path) do
    absolute = Path.expand(path)
    encoded = URI.encode(absolute)
    "file:#{encoded}?mode=ro&immutable=1"
  end

  defp enable_query_only!(conn) do
    case Exqlite.Sqlite3.execute(conn, "PRAGMA query_only = ON") do
      :ok ->
        verify_query_only(conn)

      {:error, reason} ->
        {:error, {:query_only_failed, reason}}
    end
  end

  defp verify_query_only(conn) do
    case query_rows(conn, "PRAGMA query_only") do
      {:ok, [[1]]} -> :ok
      {:ok, [[value]]} when value in ["1", 1] -> :ok
      other -> {:error, {:query_only_not_enabled, other}}
    end
  end

  defp snapshot_source(source_path) do
    if force_snapshot_failure?() do
      {:error, {:snapshot_failed, "test"}}
    else
      do_snapshot_source(source_path)
    end
  end

  defp force_snapshot_failure? do
    Application.get_env(:dnc_watchdog, :allow_test_sqlite_hooks, false) and
      Process.get(:dnc_watchdog_force_snapshot_failure) == true
  end

  defp do_snapshot_source(source_path) do
    unless File.exists?(source_path) do
      {:error, {:source_not_found, source_path}}
    else
      snapshot_path =
        Path.join(
          System.tmp_dir!(),
          "dnc_watchdog-ro-#{:erlang.unique_integer([:positive])}-#{Path.basename(source_path)}"
        )

      File.cp!(source_path, snapshot_path)

      for suffix <- ["-wal", "-shm"] do
        sidecar = source_path <> suffix

        if File.exists?(sidecar) do
          File.cp!(sidecar, snapshot_path <> suffix)
        end
      end

      {:ok, snapshot_path}
    end
  rescue
    error ->
      {:error, {:snapshot_failed, Exception.message(error)}}
  end

  defp cleanup_snapshot(snapshot_path) do
    for path <- [snapshot_path, snapshot_path <> "-wal", snapshot_path <> "-shm"] do
      if File.exists?(path), do: File.rm(path)
    end

    :ok
  end
end

defmodule DncWatchdog.Enforcement.SqliteTest do
  use ExUnit.Case, async: true

  alias DncWatchdog.Enforcement.Sqlite
  alias DncWatchdog.SqliteFixtures

  setup do
    dir = SqliteFixtures.temp_dir!()
    on_exit(fn -> File.rm_rf(dir) end)
    source = Path.join(dir, "source.db")

    SqliteFixtures.write_source_db(
      source,
      "CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT); INSERT INTO items (id, name) VALUES (1, 'alpha');"
    )

    %{source: source, dir: dir}
  end

  test "with_connection/2 reads without modifying source file", %{source: source} do
    before = File.read!(source)

    assert {:ok, tables} =
             Sqlite.with_connection(source, fn conn ->
               {:ok, Sqlite.list_tables(conn)}
             end)

    assert "items" in tables
    assert before == File.read!(source)
  end

  test "with_connection/2 returns error when source is missing" do
    assert {:error, {:source_not_found, _}} =
             Sqlite.with_connection("/nonexistent/chat.db", fn _conn -> :ok end)
  end

  test "query_only prevents writes on connection", %{source: source} do
    assert {:error, _} =
             Sqlite.with_connection(source, fn conn ->
               Exqlite.Sqlite3.execute(conn, "INSERT INTO items (id, name) VALUES (2, 'beta')")
             end)
  end

  test "cell_to_string/1 normalizes types" do
    assert Sqlite.cell_to_string(nil) == ""
    assert Sqlite.cell_to_string(42) == "42"
    assert Sqlite.cell_to_string("x") == "x"
  end

  test "query_rows/2 collects all pages of rows", %{source: source} do
    {:ok, conn} = Exqlite.Sqlite3.open(source)

    Enum.each(2..120, fn id ->
      Exqlite.Sqlite3.execute(conn, "INSERT INTO items (id, name) VALUES (#{id}, 'n#{id}')")
    end)

    Exqlite.Sqlite3.close(conn)

    assert {:ok, rows} =
             Sqlite.with_connection(source, fn ro_conn ->
               Sqlite.query_rows(ro_conn, "SELECT id FROM items ORDER BY id")
             end)

    assert length(rows) == 120
    assert hd(rows) == [1]
    assert List.last(rows) == [120]
  end

  test "with_connection/2 falls back to direct readonly when snapshot copy fails", %{source: source} do
    Process.put(:dnc_watchdog_force_snapshot_failure, true)

    try do
      assert {:ok, tables} =
               Sqlite.with_connection(source, fn conn ->
                 {:ok, Sqlite.list_tables(conn)}
               end)

      assert "items" in tables
    after
      Process.delete(:dnc_watchdog_force_snapshot_failure)
    end
  end
end

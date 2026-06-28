defmodule Mix.Tasks.Dnc.ImportLocalTest do
  use DncWatchdog.DataCase

  import ExUnit.CaptureIO

  alias DncWatchdog.SqliteFixtures

  setup do
    Mix.Task.reenable("dnc.import_local")

    dir = SqliteFixtures.temp_dir!()
    on_exit(fn -> File.rm_rf(dir) end)

    messages_db = SqliteFixtures.create_messages_db(Path.join(dir, "chat.db"))
    calls_db = SqliteFixtures.create_call_history_db(Path.join(dir, "calls.storedata"))

    %{messages_db: messages_db, calls_db: calls_db}
  end

  test "run/1 imports from explicit database paths", %{messages_db: messages_db, calls_db: calls_db} do
    output =
      capture_io(fn ->
        Mix.Task.run("dnc.import_local", [
          "--messages-db",
          messages_db,
          "--calls-db",
          calls_db,
          "--my-phone",
          "5550001234",
          "--limit",
          "10"
        ])
      end)

    assert output =~ "Skipped (you initiated): 1"
    assert output =~ "Rows imported: 2"
    assert output =~ "Communications stored: 2"
    assert output =~ messages_db
  end

  test "run/1 reports snapshot failures without crashing", %{messages_db: messages_db} do
    Process.put(:dnc_watchdog_force_snapshot_failure, true)

    try do
      output =
        capture_io(fn ->
          Mix.Task.run("dnc.import_local", [
            "--messages-db",
            messages_db,
            "--no-calls",
            "--my-phone",
            "5550001234",
            "--limit",
            "10"
          ])
        end)

      assert output =~ "Rows imported:"
      refute output =~ "Protocol.UndefinedError"
    after
      Process.delete(:dnc_watchdog_force_snapshot_failure)
    end
  end
end

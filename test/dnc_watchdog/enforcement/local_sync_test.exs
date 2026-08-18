defmodule DncWatchdog.Enforcement.LocalSyncTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.LocalImportSync
  alias DncWatchdog.Enforcement.LocalSync
  alias DncWatchdog.SqliteFixtures

  setup do
    dir = SqliteFixtures.temp_dir!()
    on_exit(fn -> File.rm_rf(dir) end)

    %{
      messages_db: SqliteFixtures.create_messages_db(Path.join(dir, "chat.db")),
      calls_db: SqliteFixtures.create_call_history_db(Path.join(dir, "calls.storedata")),
      contacts_db: SqliteFixtures.create_contacts_db(Path.join(dir, "AddressBook.sqlitedb"), [])
    }
  end

  defp sync_opts(overrides) do
    Keyword.merge(
      [
        skip_contacts: false,
        my_phone: "5550001234",
        limit: 50
      ],
      overrides
    )
  end

  test "first sync stores last_synced_at and imports rows", %{
    messages_db: messages_db,
    calls_db: calls_db
  } do
    assert %LocalImportSync{last_synced_at: nil} = LocalSync.get_state()

    assert {:ok, %{summary: summary, state: state}} =
             LocalSync.sync(
               sync_opts(messages_db: messages_db, calls_db: calls_db, lookback_days: 180)
             )

    assert summary.created_communications == 2
    assert state.last_status == "ok"
    assert state.last_synced_at
    assert Enforcement.count_communications() == 2
  end

  test "second sync with no new rows imports nothing", %{
    messages_db: messages_db,
    calls_db: calls_db
  } do
    assert {:ok, _} =
             LocalSync.sync(
               sync_opts(messages_db: messages_db, calls_db: calls_db, lookback_days: 180)
             )

    assert {:ok, %{summary: summary}} =
             LocalSync.sync(sync_opts(messages_db: messages_db, calls_db: calls_db))

    assert summary.created_communications == 0
    assert summary.message_rows == 0
    assert summary.call_rows == 0
    assert Enforcement.count_communications() == 2
  end

  test "second sync imports delayed Call History older than last sync", %{
    messages_db: messages_db
  } do
    dir = Path.dirname(messages_db)
    empty_calls = Path.join(dir, "empty-calls.storedata")
    SqliteFixtures.create_call_history_db(empty_calls, call_date: ~U[1970-01-01 00:00:00Z])

    # Wipe the ancient seed call so first sync has no calls.
    {:ok, conn} = Exqlite.Sqlite3.open(empty_calls)
    Exqlite.Sqlite3.execute(conn, "DELETE FROM ZCALLRECORD")
    Exqlite.Sqlite3.close(conn)

    assert {:ok, %{state: state}} =
             LocalSync.sync(
               sync_opts(
                 messages_db: messages_db,
                 calls_db: empty_calls,
                 messages: true,
                 calls: true
               )
             )

    before = Enforcement.count_communications()

    # Simulate Continuity: a call from 2 days ago appears on the Mac after last sync.
    delayed_at =
      DateTime.utc_now()
      |> DateTime.add(-2 * 24 * 3600, :second)
      |> DateTime.truncate(:second)

    SqliteFixtures.insert_call_record(empty_calls, %{
      call_date: delayed_at,
      address: "+14158535343",
      name: "San Francisco CA",
      pk: 99
    })

    previous = Application.get_env(:dnc_watchdog, :local_sync, [])

    Application.put_env(
      :dnc_watchdog,
      :local_sync,
      Keyword.merge(previous, overlap_seconds: 3600, call_overlap_seconds: 259_200)
    )

    on_exit(fn -> Application.put_env(:dnc_watchdog, :local_sync, previous) end)

    assert state.last_synced_at

    assert {:ok, %{summary: summary}} =
             LocalSync.sync(
               sync_opts(
                 messages_db: messages_db,
                 calls_db: empty_calls,
                 messages: false,
                 calls: true
               )
             )

    assert summary.call_rows == 1
    assert summary.created_communications == 1
    assert Enforcement.count_communications() == before + 1
  end

  test "second sync imports delayed Messages older than last sync", %{
    calls_db: calls_db
  } do
    dir = Path.dirname(calls_db)
    messages_db = Path.join(dir, "delayed-chat.db")
    SqliteFixtures.create_messages_db(messages_db)

    {:ok, conn} = Exqlite.Sqlite3.open(messages_db)
    Exqlite.Sqlite3.execute(conn, "DELETE FROM message")
    Exqlite.Sqlite3.execute(conn, "DELETE FROM chat_message_join")
    Exqlite.Sqlite3.close(conn)

    assert {:ok, %{state: state}} =
             LocalSync.sync(
               sync_opts(
                 messages_db: messages_db,
                 calls_db: calls_db,
                 messages: true,
                 calls: false
               )
             )

    before = Enforcement.count_communications()

    delayed_at =
      DateTime.utc_now()
      |> DateTime.add(-2 * 24 * 3600, :second)
      |> DateTime.truncate(:second)

    SqliteFixtures.insert_message(messages_db, %{
      date: delayed_at,
      text: "Delayed Continuity SMS",
      is_from_me: 0,
      handle_id: 1,
      rowid: 99
    })

    previous = Application.get_env(:dnc_watchdog, :local_sync, [])

    Application.put_env(
      :dnc_watchdog,
      :local_sync,
      Keyword.merge(previous, overlap_seconds: 259_200, call_overlap_seconds: 3600)
    )

    on_exit(fn -> Application.put_env(:dnc_watchdog, :local_sync, previous) end)

    assert state.last_synced_at

    assert {:ok, %{summary: summary}} =
             LocalSync.sync(
               sync_opts(
                 messages_db: messages_db,
                 calls_db: calls_db,
                 messages: true,
                 calls: false
               )
             )

    assert summary.message_rows == 1
    assert summary.created_communications == 1
    assert Enforcement.count_communications() == before + 1
  end

  test "explicit lookback_days ignores last_synced_at cutoff", %{
    messages_db: messages_db,
    calls_db: calls_db
  } do
    assert {:ok, _} =
             LocalSync.sync(
               sync_opts(
                 messages_db: messages_db,
                 calls_db: calls_db,
                 messages: false,
                 calls: false
               )
             )

    # Seed a message from 10 days ago after sync advanced last_synced_at.
    delayed_at =
      DateTime.utc_now()
      |> DateTime.add(-10 * 24 * 3600, :second)
      |> DateTime.truncate(:second)

    {:ok, conn} = Exqlite.Sqlite3.open(messages_db)
    Exqlite.Sqlite3.execute(conn, "DELETE FROM message")
    Exqlite.Sqlite3.close(conn)

    SqliteFixtures.insert_message(messages_db, %{
      date: delayed_at,
      text: "Explicit lookback SMS",
      is_from_me: 0,
      handle_id: 1,
      rowid: 42
    })

    previous = Application.get_env(:dnc_watchdog, :local_sync, [])

    Application.put_env(
      :dnc_watchdog,
      :local_sync,
      Keyword.merge(previous, overlap_seconds: 3600, call_overlap_seconds: 3600)
    )

    on_exit(fn -> Application.put_env(:dnc_watchdog, :local_sync, previous) end)

    # Incremental sync (1h overlap) should miss a 10-day-old message.
    assert {:ok, %{summary: missed}} =
             LocalSync.sync(
               sync_opts(
                 messages_db: messages_db,
                 calls_db: calls_db,
                 messages: true,
                 calls: false
               )
             )

    assert missed.message_rows == 0

    assert {:ok, %{summary: found}} =
             LocalSync.sync(
               sync_opts(
                 messages_db: messages_db,
                 calls_db: calls_db,
                 messages: true,
                 calls: false,
                 lookback_days: 14
               )
             )

    assert found.message_rows == 1
    assert found.created_communications == 1
    assert found.lookback_days == 14
  end

  test "summary_message/1 describes import results" do
    assert LocalSync.summary_message(%{
             created_communications: 3,
             skipped_duplicates: 2,
             message_rows: 5,
             call_rows: 1
           }) =~ "Imported 3 new"

    assert LocalSync.summary_message(%{
             created_communications: 0,
             skipped_duplicates: 0,
             message_rows: 0,
             call_rows: 0
           }) =~ "Imported 0 new"
  end

  test "summary_message/1 notes when contacts are included" do
    message =
      LocalSync.summary_message(%{
        created_communications: 1,
        message_rows: 1,
        call_rows: 0,
        logs: [{:contacts_disabled, "Contact filtering disabled"}]
      })

    assert message =~ "including contacts"
  end

  test "summary_message/1 includes newest Mac call timestamp" do
    message =
      LocalSync.summary_message(%{
        created_communications: 0,
        message_rows: 0,
        call_rows: 2,
        newest_call_at: "2026-07-06 19:56:31"
      })

    assert message =~ "newest Mac call 2026-07-06 19:56:31"
  end

  test "summary_message/1 explains contact skips" do
    message =
      LocalSync.summary_message(%{
        created_communications: 0,
        skipped_contacts: 364,
        message_rows: 10,
        call_rows: 5
      })

    assert message =~ "364 contact(s) skipped"
    assert message =~ "Include contacts"
  end

  test "summary_message/1 warns when contacts were not loaded" do
    message =
      LocalSync.summary_message(%{
        created_communications: 1,
        logs: [{:contacts_empty, "No contact phones or emails loaded"}]
      })

    assert message =~ "No contacts loaded"
  end
end

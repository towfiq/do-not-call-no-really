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
        limit: 50,
        lookback_days: 180
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
             LocalSync.sync(sync_opts(messages_db: messages_db, calls_db: calls_db))

    assert summary.created_communications == 2
    assert state.last_status == "ok"
    assert state.last_synced_at
    assert Enforcement.count_communications() == 2
  end

  test "second sync with no new rows imports nothing", %{
    messages_db: messages_db,
    calls_db: calls_db
  } do
    assert {:ok, _} = LocalSync.sync(sync_opts(messages_db: messages_db, calls_db: calls_db))

    assert {:ok, %{summary: summary}} =
             LocalSync.sync(sync_opts(messages_db: messages_db, calls_db: calls_db))

    assert summary.created_communications == 0
    assert summary.message_rows == 0
    assert summary.call_rows == 0
    assert Enforcement.count_communications() == 2
  end

  test "summary_message/1 describes import results" do
    assert LocalSync.summary_message(%{created_communications: 3, skipped_duplicates: 2}) =~
             "Imported 3 new"

    assert LocalSync.summary_message(%{created_communications: 0, skipped_duplicates: 0}) =~
             "Imported 0 new"
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

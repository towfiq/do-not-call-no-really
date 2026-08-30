defmodule DncWatchdog.Enforcement.LocalImporterTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.LocalImporter
  alias DncWatchdog.SqliteFixtures

  setup do
    dir = SqliteFixtures.temp_dir!()
    on_exit(fn -> File.rm_rf(dir) end)

    messages_db = SqliteFixtures.create_messages_db(Path.join(dir, "chat.db"))
    calls_db = SqliteFixtures.create_call_history_db(Path.join(dir, "calls.storedata"))
    contacts_db = SqliteFixtures.create_contacts_db(Path.join(dir, "AddressBook.sqlitedb"), [])

    %{
      messages_db: messages_db,
      calls_db: calls_db,
      contacts_db: contacts_db
    }
  end

  test "import_local/1 imports from fixture sqlite databases", %{
    messages_db: messages_db,
    calls_db: calls_db
  } do
    summary =
      LocalImporter.import_local(
        messages_db: messages_db,
        calls_db: calls_db,
        skip_contacts: false,
        my_phone: "5550001234",
        limit: 50
      )

    assert summary.message_rows == 2
    assert summary.call_rows == 1
    assert summary.skipped_self_initiated == 1
    assert summary.rows == 2
    assert summary.created_communications == 2
    assert length(Enforcement.list_cases()) >= 2
    assert Enum.any?(summary.logs, fn {:ok, _, _, _} -> true end)
  end

  test "import_local/1 with lookback_days skips older fixture rows", %{
    messages_db: messages_db,
    calls_db: calls_db
  } do
    summary =
      LocalImporter.import_local(
        messages_db: messages_db,
        calls_db: calls_db,
        skip_contacts: false,
        skip_self_initiated: false,
        my_phone: "5550001234",
        lookback_days: 7,
        limit: 50
      )

    assert summary.message_rows == 0
    assert summary.call_rows == 0
    assert summary.rows == 0
  end

  test "format_error/1 formats tuple errors as strings" do
    assert LocalImporter.format_error({:snapshot_failed, "not owner"}) =~ "not owner"
    assert LocalImporter.format_error({:snapshot_failed, "not owner"}) =~ "copy database"

    assert LocalImporter.format_error({:database_open_failed, {:snapshot_failed, "x"}}) =~
             "read-only"
  end

  test "import_local/1 can skip messages", %{calls_db: calls_db} do
    summary =
      LocalImporter.import_local(
        messages: false,
        calls_db: calls_db,
        skip_contacts: false,
        my_phone: "5550001234"
      )

    assert summary.message_rows == 0
    assert summary.call_rows == 1
  end

  test "import_local/1 skips rows from macOS Contacts when skip_contacts is true", %{
    messages_db: messages_db,
    calls_db: calls_db,
    contacts_db: contacts_db
  } do
    contacts_db =
      SqliteFixtures.create_contacts_db(contacts_db, ["+1-800-123-4567"])

    summary =
      LocalImporter.import_local(
        messages_db: messages_db,
        calls_db: calls_db,
        contacts_dbs: [contacts_db],
        skip_contacts: true,
        my_phone: "5550001234",
        limit: 50
      )

    assert summary.message_rows == 2
    assert summary.skipped_contacts == 1
    assert summary.skipped_self_initiated == 1
    assert summary.rows == 1
    assert summary.created_communications == 1
  end

  test "import_local/1 includes rows from contacts whose company contains dnc", %{
    messages_db: messages_db,
    calls_db: calls_db,
    contacts_db: contacts_db
  } do
    contacts_db =
      SqliteFixtures.create_contacts_db(
        contacts_db,
        ["+1-800-123-4567"],
        [],
        %{organization: "Spam DNC Caller Inc"}
      )

    summary =
      LocalImporter.import_local(
        messages_db: messages_db,
        calls_db: calls_db,
        contacts_dbs: [contacts_db],
        skip_contacts: true,
        my_phone: "5550001234",
        limit: 50
      )

    assert summary.skipped_contacts == 0
    assert summary.rows == 2
    assert summary.created_communications == 2
  end

  test "import_local/1 includes outgoing when skip_self_initiated is false", %{
    messages_db: messages_db,
    calls_db: calls_db
  } do
    summary =
      LocalImporter.import_local(
        messages_db: messages_db,
        calls_db: calls_db,
        skip_contacts: false,
        skip_self_initiated: false,
        my_phone: "5550001234",
        limit: 50
      )

    assert summary.skipped_self_initiated == 0
    assert summary.rows == 3
  end
end

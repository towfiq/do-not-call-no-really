defmodule DncWatchdog.Enforcement.Local.PathsTest do
  use ExUnit.Case, async: true

  alias DncWatchdog.Enforcement.Local.Paths
  alias DncWatchdog.SqliteFixtures

  test "messages_db/1 uses override when provided" do
    assert Paths.messages_db("/tmp/custom-chat.db") == "/tmp/custom-chat.db"
  end

  test "messages_db/0 expands default path" do
    path = Paths.messages_db()
    assert String.ends_with?(path, "Library/Messages/chat.db")
  end

  test "default_call_history_paths/0 returns known locations" do
    paths = Paths.default_call_history_paths()
    assert Enum.any?(paths, &String.contains?(&1, "CallHistory"))
  end

  test "discover_contacts_dbs_under/1 finds legacy and modern AddressBook databases" do
    dir = SqliteFixtures.temp_dir!()
    on_exit(fn -> File.rm_rf(dir) end)

    legacy = Path.join(dir, "AddressBook.sqlitedb")
    modern = Path.join([dir, "Sources", "ABC", "AddressBook-v22.abcddb"])
    File.mkdir_p!(Path.dirname(modern))
    File.write!(legacy, "")
    File.write!(modern, "")

    assert Paths.discover_contacts_dbs_under(dir) == [legacy, modern]
  end
end

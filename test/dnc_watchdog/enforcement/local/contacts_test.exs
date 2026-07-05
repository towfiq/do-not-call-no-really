defmodule DncWatchdog.Enforcement.Local.ContactsTest do
  use ExUnit.Case, async: true

  alias DncWatchdog.Enforcement.Local.Contacts
  alias DncWatchdog.SqliteFixtures

  test "load/1 reads phones and emails from fixture database" do
    dir = SqliteFixtures.temp_dir!()
    on_exit(fn -> File.rm_rf(dir) end)

    path =
      SqliteFixtures.create_contacts_db(
        Path.join(dir, "AddressBook.sqlitedb"),
        ["+1-800-123-4567"],
        ["Friend@Example.com"]
      )

    assert {:ok, set, [^path]} = Contacts.load(contacts_dbs: [path])
    assert MapSet.member?(set.phones, "8001234567")
    assert MapSet.member?(set.phones, "18001234567")
    assert MapSet.member?(set.emails, "friend@example.com")
  end

  test "load/1 reads phones stored as area code and local number", %{} do
    dir = SqliteFixtures.temp_dir!()
    on_exit(fn -> File.rm_rf(dir) end)

    path = SqliteFixtures.create_split_phone_contacts_db(Path.join(dir, "AddressBook-v22.abcddb"), "323", "4812617")

    assert {:ok, set, [^path]} = Contacts.load(contacts_dbs: [path])
    assert MapSet.member?(set.phones, "3234812617")
    assert MapSet.member?(set.phones, "13234812617")
  end

  test "load/1 returns empty set when no databases exist" do
    assert {:ok, set, []} = Contacts.load(contacts_dbs: [])
    assert MapSet.size(set.phones) == 0
  end
end

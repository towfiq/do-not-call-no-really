defmodule DncWatchdog.Enforcement.Local.MeCardTest do
  use ExUnit.Case, async: true

  alias DncWatchdog.Enforcement.Local.MeCard
  import DncWatchdog.SqliteFixtures

  test "read/1 loads the macOS Contacts Me card" do
    dir = temp_dir!("me_card")
    path = create_me_card_contacts_db(Path.join(dir, "AddressBook-v22.abcddb"))

    assert {:ok, card} = MeCard.read(contacts_dbs: [path])
    assert card.name == "Mark Example"
    assert card.address == "123 Oak St\nPalo Alto, CA 94301"
    assert card.phone == "4159719595"
    assert card.email == "mark@example.com"
  end

  test "read/1 returns not_found when no Me card exists" do
    dir = temp_dir!("me_card_empty")
    path = create_contacts_db(Path.join(dir, "AddressBook-v22.abcddb"))

    assert {:error, :not_found} = MeCard.read(contacts_dbs: [path])
  end
end

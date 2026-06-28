defmodule Mix.Tasks.DncPurgeContactsTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.Phone

  import DncWatchdog.EnforcementFixtures

  test "run/1 removes contact communications with contact_set via purge module" do
    communication_fixture(%{direction: "incoming", from_number: "8001234567"})
    communication_fixture(%{direction: "incoming", from_number: "9999999999"})

    contacts = %{
      phones: MapSet.new(Phone.lookup_keys("+1-800-123-4567")),
      emails: MapSet.new()
    }

    assert {:ok, summary} = DncWatchdog.Enforcement.PurgeContacts.purge(contact_set: contacts)
    assert summary.deleted == 1
    assert Enforcement.count_communications() == 1
  end
end

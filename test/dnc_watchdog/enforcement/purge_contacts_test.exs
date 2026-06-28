defmodule DncWatchdog.Enforcement.PurgeContactsTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.ContactFilter
  alias DncWatchdog.Enforcement.Phone
  alias DncWatchdog.Enforcement.PurgeContacts
  alias DncWatchdog.Repo

  import DncWatchdog.EnforcementFixtures

  setup do
    contact_set = %{
      phones: MapSet.new(Phone.lookup_keys("+1-800-123-4567")),
      emails: MapSet.new()
    }

    %{contacts: contact_set}
  end

  test "purge/1 deletes communications from macOS Contacts", %{contacts: contacts} do
    contact = communication_fixture(%{direction: "incoming", from_number: "8001234567"})
    _other = communication_fixture(%{direction: "incoming", from_number: "9999999999"})

    assert {:ok, summary} = PurgeContacts.purge(contact_set: contacts)
    assert summary.matched == 1
    assert summary.deleted == 1
    assert summary.remaining == 1
    assert Enforcement.count_communications() == 1
    refute Repo.get(DncWatchdog.Enforcement.Communication, contact.id)
  end

  test "purge/1 removes cases that become empty", %{contacts: contacts} do
    communication_fixture(%{direction: "incoming", from_number: "8001234567"})
    other = communication_fixture(%{direction: "incoming", from_number: "9999999999"})

    assert {:ok, summary} = PurgeContacts.purge(contact_set: contacts)
    assert summary.cases_deleted == 1
    assert Repo.get(DncWatchdog.Enforcement.Case, other.case_id)
  end

  test "purge/1 dry_run does not delete", %{contacts: contacts} do
    communication_fixture(%{direction: "incoming", from_number: "8001234567"})

    assert {:ok, summary} = PurgeContacts.purge(contact_set: contacts, dry_run: true)
    assert summary.deleted == 1
    assert summary.cases_deleted == 1
    assert Enforcement.count_communications() == 1
  end

  test "purge/1 matches the same rows as ContactFilter", %{contacts: contacts} do
    comm = communication_fixture(%{direction: "incoming", from_number: "6504653718"})

    refute ContactFilter.contact_row?(
             %{direction: comm.direction, from_number: comm.from_number, to_number: comm.to_number},
             contacts
           )

    matching = %{
      phones: MapSet.new(Phone.lookup_keys("6504653718")),
      emails: MapSet.new()
    }

    assert {:ok, summary} = PurgeContacts.purge(contact_set: matching)
    assert summary.deleted == 1
  end
end

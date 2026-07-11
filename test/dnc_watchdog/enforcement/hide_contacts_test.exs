defmodule DncWatchdog.Enforcement.HideContactsTest do
  use DncWatchdog.DataCase

  import DncWatchdog.EnforcementFixtures

  alias DncWatchdog.Enforcement

  test "list_communications/1 hides peers in contact_set when hide_contacts is true" do
    contact = communication_fixture(%{from_number: "8001234567", body: "from contact"})
    other = communication_fixture(%{from_number: "9999999999", body: "not a contact"})

    contact_set = %{
      phones: MapSet.new(["8001234567"]),
      emails: MapSet.new()
    }

    hidden =
      Enforcement.list_communications(
        hide_contacts: true,
        hide_excluded: false,
        contact_set: contact_set
      )

    assert Enum.any?(hidden, &(&1.id == other.id))
    refute Enum.any?(hidden, &(&1.id == contact.id))

    shown =
      Enforcement.list_communications(
        hide_contacts: false,
        hide_excluded: false,
        contact_set: contact_set
      )

    assert Enum.any?(shown, &(&1.id == contact.id))
    assert Enum.any?(shown, &(&1.id == other.id))
  end

  test "count_communications/1 respects hide_contacts" do
    communication_fixture(%{from_number: "8001234567"})
    communication_fixture(%{from_number: "9999999999"})

    contact_set = %{
      phones: MapSet.new(["8001234567"]),
      emails: MapSet.new()
    }

    assert Enforcement.count_communications(
             hide_contacts: true,
             hide_excluded: false,
             contact_set: contact_set
           ) == 1

    assert Enforcement.count_communications(
             hide_contacts: false,
             hide_excluded: false,
             contact_set: contact_set
           ) == 2
  end
end

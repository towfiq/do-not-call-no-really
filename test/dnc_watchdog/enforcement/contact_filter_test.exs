defmodule DncWatchdog.Enforcement.ContactFilterTest do
  use ExUnit.Case, async: true

  alias DncWatchdog.Enforcement.ContactFilter
  alias DncWatchdog.Enforcement.Phone

  setup do
    set = %{
      phones: MapSet.new(["8001234567"]),
      emails: MapSet.new(["friend@example.com"])
    }

    %{contacts: set}
  end

  test "contact_row?/2 matches normalized phone peers", %{contacts: contacts} do
    row = %{
      direction: "incoming",
      from_number: "+1-800-123-4567",
      to_number: "5550001234"
    }

    assert ContactFilter.contact_row?(row, contacts)
  end

  test "contact_row?/2 matches 10-digit message peers to +1 contacts", %{contacts: contacts} do
    row = %{
      direction: "incoming",
      from_number: "8001234567",
      to_number: "5550001234"
    }

    assert ContactFilter.contact_row?(row, contacts)
  end

  test "contact_row?/2 matches +1 message peers to 10-digit contacts" do
    contacts = %{
      phones: MapSet.new(Phone.lookup_keys("8001234567")),
      emails: MapSet.new()
    }

    row = %{
      direction: "incoming",
      from_number: "+18001234567",
      to_number: "5550001234"
    }

    assert ContactFilter.contact_row?(row, contacts)
  end

  test "contact_row?/2 matches email peers", %{contacts: contacts} do
    row = %{
      direction: "incoming",
      from_number: "friend@example.com",
      to_number: ""
    }

    assert ContactFilter.contact_row?(row, contacts)
  end

  test "reject_contacts/2 removes matching rows", %{contacts: contacts} do
    rows = [
      %{direction: "incoming", from_number: "8001234567", to_number: "1"},
      %{direction: "incoming", from_number: "9999999999", to_number: "1"}
    ]

    {kept, skipped} = ContactFilter.reject_contacts(rows, contacts)
    assert length(kept) == 1
    assert skipped == 1
    assert hd(kept).from_number == "9999999999"
  end

  test "reject_contact_communications/2 filters structs", %{contacts: contacts} do
    communications = [
      %{direction: "incoming", from_number: "8001234567", to_number: "1"},
      %{direction: "incoming", from_number: "9999999999", to_number: "1"}
    ]

    kept = ContactFilter.reject_contact_communications(communications, contacts)
    assert length(kept) == 1
    assert hd(kept).from_number == "9999999999"
  end
end

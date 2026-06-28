defmodule DncWatchdog.Enforcement.ExcludedSenderTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.ExcludedSender
  alias DncWatchdog.Enforcement.RowImporter
  import DncWatchdog.EnforcementFixtures

  test "exclude_all_from_peer/1 persists sender for future imports" do
    assert {:ok, 0} = Enforcement.exclude_all_from_peer("8005551212")
    assert [%{display_peer: "8005551212"}] = Enforcement.list_excluded_senders()

    summary = RowImporter.import_rows([import_row_attrs(%{from_number: "8005551212"})])

    assert summary.created_communications == 1

    [comm] = Enforcement.list_communications(hide_excluded: false)
    assert comm.violation_status == "excluded"
  end

  test "exclude_all_from_peer/1 still updates existing communications" do
    communication_fixture(%{from_number: "8001112222", violation_status: "pending"})

    assert {:ok, 1} = Enforcement.exclude_all_from_peer("8001112222")
    assert Enforcement.excluded_sender?("8001112222")
  end

  test "remove_excluded_sender stops auto-excluding on import" do
    {:ok, sender} = Enforcement.add_excluded_sender("8007778888")
    Enforcement.remove_excluded_sender(sender)

    RowImporter.import_rows([import_row_attrs(%{from_number: "8007778888"})])
    [comm] = Enforcement.list_communications(hide_excluded: false)
    assert comm.violation_status == "pending"
  end

  test "peer_key normalizes phone numbers" do
    assert ExcludedSender.peer_key("+1 (800) 555-1212") == "8005551212"
    assert ExcludedSender.peer_key("Friend@example.com") == "friend@example.com"
  end
end

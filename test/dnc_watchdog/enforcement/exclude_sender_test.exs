defmodule DncWatchdog.Enforcement.ExcludeSenderTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  import DncWatchdog.EnforcementFixtures

  test "exclude_all_from_peer/1 marks all rows from the same phone" do
    communication_fixture(%{
      direction: "incoming",
      from_number: "8001112222",
      violation_status: "pending"
    })

    communication_fixture(%{
      direction: "incoming",
      from_number: "8001112222",
      violation_status: "violation",
      body: "second spam"
    })

    communication_fixture(%{
      direction: "incoming",
      from_number: "8009998888",
      violation_status: "pending"
    })

    assert {:ok, 2} = Enforcement.exclude_all_from_peer("8001112222")

    assert Enforcement.excluded_sender?("8001112222")
    assert Enforcement.count_communications(hide_excluded: false, violations_only: false) == 3

    excluded =
      Enforcement.list_communications(hide_excluded: false)
      |> Enum.filter(&(&1.violation_status == "excluded"))

    assert length(excluded) == 2
    assert Enum.all?(excluded, &(&1.from_number == "8001112222"))
  end

  test "exclude_all_from_peer_for_communication/1 uses outgoing to_number as peer" do
    comm =
      communication_fixture(%{
        direction: "outgoing",
        from_number: "4159719595",
        to_number: "7818661626",
        violation_status: "pending"
      })

    assert {:ok, 1} = Enforcement.exclude_all_from_peer_for_communication(comm)
    assert Repo.get!(DncWatchdog.Enforcement.Communication, comm.id).violation_status == "excluded"
  end
end

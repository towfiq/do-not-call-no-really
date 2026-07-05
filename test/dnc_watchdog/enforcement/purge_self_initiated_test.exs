defmodule DncWatchdog.Enforcement.PurgeSelfInitiatedTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.Communication
  alias DncWatchdog.Enforcement.PurgeSelfInitiated
  alias DncWatchdog.Repo

  import DncWatchdog.EnforcementFixtures

  test "purge/1 deletes outgoing and from-my-phone rows" do
    incoming = communication_fixture(%{direction: "incoming", from_number: "8001234567"})

    _outgoing =
      communication_fixture(%{
        direction: "outgoing",
        from_number: "4159719595",
        to_number: "7818661626"
      })

    assert {:ok, summary} = PurgeSelfInitiated.purge(my_phone: "4159719595")
    assert summary.matched == 1
    assert summary.deleted == 1
    assert summary.remaining == 1
    assert Enforcement.count_communications() == 1
    assert Repo.get!(Communication, incoming.id)
  end

  test "purge/1 dry_run does not delete" do
    communication_fixture(%{direction: "outgoing", from_number: "4159719595"})

    assert {:ok, summary} = PurgeSelfInitiated.purge(my_phone: "4159719595", dry_run: true)
    assert summary.deleted == 1
    assert Enforcement.count_communications() == 1
  end

  test "purge/1 requires my_phone" do
    assert {:error, :my_phone_required} = PurgeSelfInitiated.purge(my_phone: "")
  end
end

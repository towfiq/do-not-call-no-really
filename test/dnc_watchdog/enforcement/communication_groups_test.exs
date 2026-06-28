defmodule DncWatchdog.Enforcement.CommunicationGroupsTest do
  use ExUnit.Case, async: true

  alias DncWatchdog.Enforcement.CommunicationGroups

  test "group_by_peer/1 groups incoming and outgoing by the other party" do
    older = ~N[2026-06-01 10:00:00]
    newer = ~N[2026-06-09 12:00:00]
    newest = ~N[2026-06-09 18:00:00]

    communications = [
      %{id: 1, direction: "incoming", from_number: "8187432556", to_number: "4159719595", timestamp: older},
      %{id: 2, direction: "incoming", from_number: "8187432556", to_number: "4159719595", timestamp: newer},
      %{id: 3, direction: "incoming", from_number: "8001112222", to_number: "4159719595", timestamp: newer},
      %{id: 4, direction: "outgoing", from_number: "4159719595", to_number: "8187432556", timestamp: newest}
    ]

    groups = CommunicationGroups.group_by_peer(communications)

    assert length(groups) == 2

    annie = Enum.find(groups, &(&1.peer == "8187432556"))
    assert length(annie.communications) == 3
    assert annie.latest.id == 4
    assert Enum.map(annie.communications, & &1.id) == [4, 2, 1]

    other = Enum.find(groups, &(&1.peer == "8001112222"))
    assert length(other.communications) == 1
  end
end

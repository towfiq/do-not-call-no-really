defmodule DncWatchdog.Enforcement.SelfInitiatedFilterTest do
  use ExUnit.Case, async: true

  alias DncWatchdog.Enforcement.SelfInitiatedFilter

  test "reject_self_initiated/2 drops outgoing rows when my_phone is set" do
    rows = [
      %{direction: "incoming", from_number: "8001234567", to_number: "4159719595"},
      %{direction: "outgoing", from_number: "4159719595", to_number: "7818661626"}
    ]

    {kept, skipped} = SelfInitiatedFilter.reject_self_initiated(rows, "4159719595")

    assert length(kept) == 1
    assert skipped == 1
    assert hd(kept).direction == "incoming"
  end

  test "reject_self_initiated/2 is a no-op when my_phone is blank" do
    rows = [%{direction: "outgoing", from_number: "", to_number: "8001234567"}]

    assert {^rows, 0} = SelfInitiatedFilter.reject_self_initiated(rows, "")
  end
end

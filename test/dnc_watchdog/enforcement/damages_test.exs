defmodule DncWatchdog.Enforcement.DamagesTest do
  use ExUnit.Case, async: true

  alias DncWatchdog.Enforcement.Damages

  test "counts $1,500 per violation" do
    comms = [
      %{violation_status: "violation"},
      %{violation_status: "pending"},
      %{violation_status: "excluded"},
      %{violation_status: "violation"}
    ]

    assert Damages.count(comms) == 2
    assert Decimal.equal?(Damages.total(comms), Decimal.new("3000.00"))
    assert Damages.format(Damages.total(comms)) == "$3,000.00"
    assert Damages.format_row(%{violation_status: "violation"}) == "$1,500.00"
    assert Damages.format_row(%{violation_status: "pending"}) == "—"
  end

  test "for_case uses preloaded communications" do
    case = %{
      communications: [
        %{violation_status: "violation"},
        %{violation_status: "pending"}
      ]
    }

    assert Damages.format(Damages.for_case(case)) == "$1,500.00"
  end
end

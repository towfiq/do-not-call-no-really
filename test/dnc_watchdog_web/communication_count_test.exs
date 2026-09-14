defmodule DncWatchdogWeb.CommunicationCountTest do
  use ExUnit.Case, async: true

  alias DncWatchdogWeb.CommunicationCount

  test "filters and sorts items by count" do
    items = [%{n: 1}, %{n: 3}, %{n: 2}]

    assert CommunicationCount.apply_count(items, 2, nil, :desc, & &1.n) == [%{n: 3}, %{n: 2}]

    assert CommunicationCount.apply_count(items, nil, "communications", :desc, & &1.n) == [
             %{n: 3},
             %{n: 2},
             %{n: 1}
           ]

    assert CommunicationCount.apply_count(items, nil, "communications", :asc, & &1.n) == [
             %{n: 1},
             %{n: 2},
             %{n: 3}
           ]
  end
end

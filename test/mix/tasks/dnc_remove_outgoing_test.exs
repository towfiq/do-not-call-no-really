defmodule Mix.Tasks.Dnc.RemoveOutgoingTest do
  use DncWatchdog.DataCase

  import ExUnit.CaptureIO
  import DncWatchdog.EnforcementFixtures

  alias DncWatchdog.Enforcement

  setup do
    Mix.Task.reenable("dnc.remove_outgoing")
    :ok
  end

  test "run/1 removes outgoing rows for my_phone" do
    communication_fixture(%{direction: "incoming", from_number: "8001234567"})
    communication_fixture(%{direction: "outgoing", from_number: "4159719595"})

    output =
      capture_io(fn ->
        Mix.Task.run("dnc.remove_outgoing", ["--my-phone", "4159719595"])
      end)

    assert output =~ "Rows removed: 1"
    assert output =~ "Remaining: 1"
    assert Enforcement.count_communications() == 1
  end

  test "run/1 --dry-run leaves rows in place" do
    communication_fixture(%{direction: "outgoing", from_number: "4159719595"})

    output =
      capture_io(fn ->
        Mix.Task.run("dnc.remove_outgoing", ["--my-phone", "4159719595", "--dry-run"])
      end)

    assert output =~ "Dry run"
    assert Enforcement.count_communications() == 1
  end
end

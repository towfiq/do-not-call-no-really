defmodule Mix.Tasks.Dnc.DedupeTest do
  use DncWatchdog.DataCase

  import ExUnit.CaptureIO
  import DncWatchdog.EnforcementFixtures

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.Communication
  alias DncWatchdog.Repo

  setup do
    Mix.Task.reenable("dnc.dedupe")
    :ok
  end

  defp insert_duplicate_communication! do
    attrs = communication_attrs()

    %Communication{}
    |> Communication.changeset(attrs)
    |> Repo.insert!()
  end

  test "run/1 prints summary after deduping" do
    insert_duplicate_communication!()
    insert_duplicate_communication!()

    output =
      capture_io(fn ->
        Mix.Task.run("dnc.dedupe", [])
      end)

    assert output =~ "Communications scanned: 2"
    assert output =~ "Rows removed: 1"
    assert Enforcement.count_communications() == 1
  end

  test "run/1 --dry-run leaves rows in place" do
    insert_duplicate_communication!()
    insert_duplicate_communication!()

    output =
      capture_io(fn ->
        Mix.Task.run("dnc.dedupe", ["--dry-run"])
      end)

    assert output =~ "Dry run"
    assert Enforcement.count_communications() == 2
  end
end

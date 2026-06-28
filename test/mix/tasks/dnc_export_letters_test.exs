defmodule Mix.Tasks.Dnc.ExportLettersTest do
  use DncWatchdog.DataCase

  import ExUnit.CaptureIO

  import DncWatchdog.EnforcementFixtures

  setup do
    Mix.Task.reenable("dnc.export_letters")

    dir = Path.join(System.tmp_dir!(), "mix_letters_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{output_dir: dir}
  end

  test "run/1 exports letters for existing cases", %{output_dir: output_dir} do
    communication_fixture(%{violation_status: "violation"})

    output =
      capture_io(fn ->
        Mix.Task.run("dnc.export_letters", [
          output_dir,
          "Test User",
          "+1-555-000-1234",
          "2020-01-01"
        ])
      end)

    assert output =~ "Letters generated: 1"
    assert Enum.any?(File.ls!(output_dir), &String.ends_with?(&1, "_demand_letter.md"))
  end

  test "run/1 prints usage when args missing" do
    output =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        Mix.Task.run("dnc.export_letters", [])
      end)

    assert output =~ "Usage: mix dnc.export_letters"
  end
end

defmodule Mix.Tasks.Dnc.ImportCsvTest do
  use DncWatchdog.DataCase

  import ExUnit.CaptureIO

  alias DncWatchdog.Enforcement

  @csv Path.expand("test/support/fixtures/sample_communications.csv", File.cwd!())

  setup do
    Mix.Task.reenable("dnc.import_csv")
    :ok
  end

  test "run/1 imports csv and prints summary" do
    output =
      capture_io(fn ->
        Mix.Task.run("dnc.import_csv", [@csv])
      end)

    assert output =~ "CSV rows imported: 3"
    assert output =~ "Communications stored: 3"
    assert length(Enforcement.list_cases()) == 3
  end

  test "run/1 prints usage without path" do
    output =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        Mix.Task.run("dnc.import_csv", [])
      end)

    assert output =~ "Usage: mix dnc.import_csv"
  end
end

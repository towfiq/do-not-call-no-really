defmodule DncWatchdog.Enforcement.LetterExporterTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement.LetterExporter
  import DncWatchdog.EnforcementFixtures

  setup do
    dir = Path.join(System.tmp_dir!(), "dnc_letters_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    %{output_dir: dir}
  end

  test "export_all/4 writes one markdown file per case", %{output_dir: output_dir} do
    communication_fixture(%{violation_status: "violation"})

    [path] =
      LetterExporter.export_all(output_dir, "Test User", "+1-555-000-1234", "2020-01-01")

    assert String.ends_with?(path, "_demand_letter.md")
    body = File.read!(path)
    assert body =~ "Fixture Company"
    assert body =~ "Test User"
    assert body =~ "CERTIFIED MAIL"
  end
end

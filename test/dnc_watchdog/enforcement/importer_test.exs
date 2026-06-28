defmodule DncWatchdog.Enforcement.ImporterTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.Importer

  @csv Path.expand("test/support/fixtures/sample_communications.csv", File.cwd!())

  test "import_csv/1 imports rows and groups unknown companies" do
    summary = Importer.import_csv(@csv)

    assert summary.rows == 3
    assert summary.created_cases == 3
    assert summary.created_communications == 3

    companies = Enforcement.list_cases() |> Enum.map(& &1.company_name) |> Enum.sort()
    assert companies == ["Acme Financial", "Acme Home Warranty", "Caller 5551112222"]
  end
end

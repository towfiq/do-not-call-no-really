defmodule DncWatchdog.Enforcement.RowImporterTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.RowImporter
  import DncWatchdog.EnforcementFixtures

  test "import_row/1 creates case and communication" do
    row = import_row_attrs()

    assert {:ok, %{case_created: true}} = RowImporter.import_row(row)
    assert [%{company_name: "Acme Imports"}] = Enforcement.list_cases()
    assert length(Enforcement.list_case_communications(hd(Enforcement.list_cases()).id)) == 1
  end

  test "import_rows/1 groups rows by company" do
    rows = [
      import_row_attrs(%{company: "Shared Co", body: "offer 1"}),
      import_row_attrs(%{company: "Shared Co", body: "offer 2"})
    ]

    summary = RowImporter.import_rows(rows)

    assert summary.rows == 2
    assert summary.created_cases == 1
    assert summary.created_communications == 2
    assert length(Enforcement.list_cases()) == 1
  end

  test "blank company incoming uses Caller phone label" do
    row =
      import_row_attrs(%{
        company: "",
        from_number: "8001234567",
        direction: "incoming"
      })

    assert {:ok, _} = RowImporter.import_row(row)
    assert [%{company_name: "Caller 8001234567"}] = Enforcement.list_cases()
  end

  test "incoming sms with marketing terms stores reasons" do
    row = import_row_attrs(%{body: "Limited time special offer", channel: "sms"})
    assert {:ok, _} = RowImporter.import_row(row)

    [comm] = Enforcement.list_case_communications(hd(Enforcement.list_cases()).id)
    assert comm.reasons =~ "marketing language"
    assert comm.reasons =~ "incoming contact"
  end

  test "short incoming call adds robocall reason" do
    row =
      import_row_attrs(%{
        channel: "call",
        duration_seconds: 5,
        body: ""
      })

    assert {:ok, _} = RowImporter.import_row(row)
    [comm] = Enforcement.list_case_communications(hd(Enforcement.list_cases()).id)
    assert comm.reasons =~ "robocall"
  end

  test "re-importing the same row does not create duplicates" do
    row = import_row_attrs()

    assert %{created_communications: 1, skipped_duplicates: 0} = RowImporter.import_rows([row])
    assert %{created_communications: 0, skipped_duplicates: 1} = RowImporter.import_rows([row])
    assert Enforcement.count_communications() == 1
  end

  test "re-importing with a different to_number does not create duplicates" do
    row = import_row_attrs(%{to_number: "local"})

    assert %{created_communications: 1} = RowImporter.import_rows([row])
    assert %{created_communications: 0, skipped_duplicates: 1} =
             RowImporter.import_rows([Map.put(row, :to_number, "4159719595")])

    assert Enforcement.count_communications() == 1
  end

  test "outgoing rows do not get solicitation reasons" do
    row = import_row_attrs(%{direction: "outgoing", body: "limited time offer"})
    assert {:ok, _} = RowImporter.import_row(row)
    [comm] = Enforcement.list_case_communications(hd(Enforcement.list_cases()).id)
    assert comm.reasons in [nil, ""]
  end
end

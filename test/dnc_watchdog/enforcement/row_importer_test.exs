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

  test "incoming call with display name joins existing Caller phone case" do
    assert {:ok, %{case_created: true}} =
             RowImporter.import_row(
               import_row_attrs(%{
                 company: "",
                 channel: "sms",
                 from_number: "8029928875",
                 body: "Stop calling me"
               })
             )

    assert {:ok, %{case_created: false}} =
             RowImporter.import_row(
               import_row_attrs(%{
                 company: "Spam Insurance LLC",
                 channel: "call",
                 from_number: "8029928875",
                 body: "",
                 duration_seconds: 12,
                 timestamp: ~N[2026-05-21 10:00:00]
               })
             )

    assert [%{company_name: "Caller 8029928875", id: case_id}] = Enforcement.list_cases()
    comms = Enforcement.list_case_communications(case_id)
    assert length(comms) == 2
    assert Enum.any?(comms, &(&1.channel == "call"))
    assert Enum.any?(comms, &(&1.channel == "sms"))
  end

  test "reconcile moves split peer communications onto one case" do
    sms_case = case_fixture(%{company_name: "Caller 8029928875"})
    call_case = case_fixture(%{company_name: "Spam Insurance LLC"})

    communication_fixture(%{
      case_id: sms_case.id,
      channel: "sms",
      direction: "incoming",
      from_number: "8029928875",
      body: "Hello"
    })

    communication_fixture(%{
      case_id: call_case.id,
      channel: "call",
      direction: "incoming",
      from_number: "8029928875",
      body: "",
      duration_seconds: 8,
      timestamp: ~N[2026-05-21 10:00:00]
    })

    assert %{peers: 1, reassigned: 1} = Enforcement.reconcile_incoming_peer_case_assignments()
    assert length(Enforcement.list_case_communications(sms_case.id)) == 2
    assert Enforcement.list_case_communications(call_case.id) == []
  end

  test "reconcile prefers Caller-labeled case over call display name" do
    caller_case = case_fixture(%{company_name: "Caller 3417869220"})
    display_case = case_fixture(%{company_name: "EQUINOX ROOFING"})

    communication_fixture(%{
      case_id: caller_case.id,
      channel: "sms",
      direction: "incoming",
      from_number: "9254996086",
      body: "Roofing promo"
    })

    communication_fixture(%{
      case_id: display_case.id,
      channel: "call",
      direction: "incoming",
      from_number: "9254996086",
      body: "",
      duration_seconds: 0,
      timestamp: ~N[2026-06-23 17:31:57]
    })

    assert %{peers: 1, reassigned: 1} = Enforcement.reconcile_incoming_peer_case_assignments()
    assert length(Enforcement.list_case_communications(caller_case.id)) == 2
    assert Enforcement.list_case_communications(display_case.id) == []
  end

  test "incoming call does not join unrelated company case without matching peer" do
    unrelated = case_fixture(%{company_name: "EQUINOX ROOFING"})

    assert {:ok, %{case_created: true}} =
             RowImporter.import_row(
               import_row_attrs(%{
                 company: "EQUINOX ROOFING",
                 channel: "call",
                 from_number: "9254996086",
                 body: "",
                 duration_seconds: 8,
                 timestamp: ~N[2026-06-23 17:31:57]
               })
             )

    assert [%{company_name: "Caller 9254996086", id: case_id} | _] =
             Enforcement.list_cases() |> Enum.filter(&(&1.company_name == "Caller 9254996086"))
    assert case_id != unrelated.id
    assert length(Enforcement.list_case_communications(case_id)) == 1
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

  test "re-importing with stale source_fingerprint does not create duplicates" do
    row = import_row_attrs()

    assert {:ok, %{duplicate: false}} = RowImporter.import_row(row)
    [existing] = Enforcement.list_case_communications(hd(Enforcement.list_cases()).id)

    {:ok, stale} =
      Enforcement.update_communication(existing, %{
        source_fingerprint: "stale-fingerprint-value"
      })

    assert stale.source_fingerprint == "stale-fingerprint-value"
    assert {:ok, %{duplicate: true}} = RowImporter.import_row(row)
    assert Enforcement.count_communications() == 1

    refreshed = Enforcement.get_communication!(existing.id)
    assert refreshed.source_fingerprint == DncWatchdog.Enforcement.Communication.fingerprint(row)
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

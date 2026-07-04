defmodule DncWatchdog.Enforcement.CivilComplaintDraftTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.CivilComplaintDraft
  alias DncWatchdog.Enforcement.FilingLimits
  import DncWatchdog.EnforcementFixtures

  test "render/4 produces civil complaint packet" do
    case =
      case_fixture(%{
        claimant_name: "Jane Doe",
        claimant_address: "123 Oak St\nPalo Alto, CA 94301",
        claimant_phone: "4159719595",
        dnc_registration_date: ~D[2020-01-01]
      })

    {:ok, case} =
      Enforcement.upsert_case_legal_entity(case, %{
        legal_name: "Acme Robocallers LLC",
        street: "123 Main St",
        city: "San Francisco",
        state: "CA",
        zip: "94105"
      })

    comm = communication_fixture(%{case_id: case.id, violation_status: "violation"})
    limits = FilingLimits.civil_assess(1)

    body = CivilComplaintDraft.render(case, [comm], [], filing_limits: limits)

    assert body =~ "CIVIL COMPLAINT FILING PACKET"
    assert body =~ "COMPLAINT"
    assert body =~ "Jane Doe"
    assert body =~ "Acme Robocallers LLC"
    assert body =~ "SUM-100"
    assert body =~ "CM-010"
    assert body =~ "CV-5012"
    assert body =~ "santaclara.courts.ca.gov"
    assert body =~ "$1500.00"
  end

  test "generate_civil_complaint_draft/1 persists draft" do
    case = case_fixture(%{claimant_name: "Jane Doe"})
    communication_fixture(%{case_id: case.id, violation_status: "violation"})

    assert {:ok, updated} = Enforcement.generate_civil_complaint_draft(case)
    assert updated.civil_complaint_draft =~ "CIVIL COMPLAINT FILING PACKET"
  end
end

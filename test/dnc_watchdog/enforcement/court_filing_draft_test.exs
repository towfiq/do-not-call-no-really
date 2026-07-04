defmodule DncWatchdog.Enforcement.CourtFilingDraftTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.CourtFilingDraft
  import DncWatchdog.EnforcementFixtures

  test "render/4 produces Santa Clara County small-claims filing packet" do
    case =
      case_fixture(%{
        claimant_name: "Jane Doe",
        claimant_address: "123 Oak St\nPalo Alto, CA 94301",
        claimant_phone: "4159719595",
        claimant_email: "jane@example.com",
        dnc_registration_date: ~D[2020-01-01],
        small_claims_county: "Santa Clara County",
        letter_draft: "Prior demand letter text"
      })

    {:ok, case} =
      Enforcement.save_mail_tracking_number(case, "9400 1118 9922 3197 4284 90")

    {:ok, case} =
      Enforcement.upsert_case_legal_entity(case, %{
        legal_name: "Acme Robocallers LLC",
        street: "123 Main St",
        city: "San Francisco",
        state: "CA",
        zip: "94105"
      })

    comm =
      communication_fixture(%{
        case_id: case.id,
        violation_status: "violation",
        body: "Limited time offer"
      })

    attachment =
      Enforcement.create_evidence_attachment!(%{
        case_id: case.id,
        filename: "screenshot.png",
        storage_path: "uploads/evidence/1/1.png",
        caption: "SMS screenshot"
      })

    body = CourtFilingDraft.render(case, [comm], [attachment])

    assert body =~ "SMALL CLAIMS FILING PACKET"
    assert body =~ "Superior Court of California, County of Santa Clara"
    assert body =~ "SC-100 FIELD WORKSHEET"
    assert body =~ "Jane Doe"
    assert body =~ "Acme Robocallers LLC"
    assert body =~ "123 Main St"
    assert body =~ "PLAINTIFF'S CLAIM AND STATEMENT OF FACTS"
    assert body =~ "DECLARATION IN SUPPORT OF CLAIM"
    assert body =~ "DAMAGES WORKSHEET"
    assert body =~ "Willful/knowing violations"
    assert body =~ "TOTAL DAMAGES AT TRIAL RATE: $1500"
    assert body =~ "AMOUNT OF CLAIM (Item 5 on SC-100):"
    assert body =~ "$1500.00"
    assert body =~ "Exhibit A: Demand letter"
    assert body =~ "9400111899223197428490"
    assert body =~ "Exhibit C: SMS screenshot"
    assert body =~ "VIOLATION SCHEDULE"
    assert body =~ "Limited time offer"
    assert body =~ "47 U.S.C. § 227"
    assert body =~ "191 North First Street"
    assert body =~ "santaclara.courts.ca.gov"
    refute body =~ "sccourt.org"
  end

  test "render/4 caps claim amount at California small claims limit" do
    case = case_fixture(%{claimant_name: "Jane Doe"})

    violations =
      for i <- 1..30 do
        communication_fixture(%{
          case_id: case.id,
          timestamp: NaiveDateTime.add(~N[2026-05-20 09:14:00], i, :day),
          violation_status: "violation"
        })
      end

    body = CourtFilingDraft.render(case, violations, [])

    refute body =~ "CLAIM AMOUNT CAPPED"
    assert body =~ "AMOUNT OF CLAIM (Item 5 on SC-100):"
    assert body =~ "$12500.00"
    assert body =~ "TOTAL DAMAGES AT TRIAL RATE: $45000"
    assert body =~ "Amount filed in small claims court (California limit): $12500.00"
  end

  test "render/4 uses $1500 per violation and references demand letter after STOP date" do
    case =
      case_fixture(%{
        claimant_name: "Jane Doe",
        stop_contact_date: ~D[2026-06-01]
      })

    before_stop =
      communication_fixture(%{
        case_id: case.id,
        timestamp: ~N[2026-05-20 09:14:00],
        violation_status: "violation"
      })

    after_stop =
      communication_fixture(%{
        case_id: case.id,
        timestamp: ~N[2026-06-10 09:14:00],
        violation_status: "violation"
      })

    body = CourtFilingDraft.render(case, [before_stop, after_stop], [])

    assert body =~ "2 violations × $1500.00 = $3000"
    assert body =~ "$1500.00"
    assert body =~ "June 1, 2026"
    assert body =~ "demand letter"
    refute body =~ "Standard ($500)"
  end

  test "generate_court_filing_draft/1 persists draft on case" do
    case = case_fixture(%{claimant_name: "Jane Doe"})
    communication_fixture(%{case_id: case.id, violation_status: "violation"})

    assert {:ok, updated} = Enforcement.generate_court_filing_draft(case)
    assert updated.court_filing_draft =~ "SMALL CLAIMS FILING PACKET"
  end

  test "generate_court_filing_draft/1 returns error without violations" do
    case = case_fixture()
    assert {:error, :no_violations} = Enforcement.generate_court_filing_draft(case)
  end
end

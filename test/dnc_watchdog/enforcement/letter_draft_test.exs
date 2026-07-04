defmodule DncWatchdog.Enforcement.LetterDraftTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.LetterDraft
  import DncWatchdog.EnforcementFixtures

  test "render/4 uses the TCPA demand letter template" do
    case =
      case_fixture(%{
        claimant_name: "Jane Doe",
        claimant_address: "123 Oak St\nPalo Alto, CA 94301",
        claimant_phone: "4159719595",
        claimant_email: "jane@example.com",
        dnc_registration_date: ~D[2020-01-01],
        small_claims_county: "Santa Clara County",
        settlement_amount: Decimal.new("900.00")
      })

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

    body = LetterDraft.render(case, [comm], [attachment])

    assert body =~ "Jane Doe"
    assert body =~ "123 Oak St"
    assert body =~ "jane@example.com"
    assert body =~ "VIA CERTIFIED MAIL"
    assert body =~ "DEMAND FOR SETTLEMENT"
    assert body =~ "47 U.S.C. § 227"
    assert body =~ "Dear Legal Department / Management"
    assert body =~ "never registered to receive marketing or other communications from you"
    assert body =~ "Applicable Violations of Federal Law"
    assert body =~ "Section 227(b)(1)(A)(iii)"
    assert body =~ "automatic telephone dialing system or an artificial or prerecorded voice"
    assert body =~ "Section 227(c)(5)"
    assert body =~ "national do-not-call registry"
    assert body =~ "Section 227(b)(3)"
    assert body =~ "$500 in damages for each such violation"
    assert body =~ "National Do Not Call Registry since January 1, 2020"
    assert body =~ "1 Standard Violations × $500 = $500"
    assert body =~ "TOTAL STATUTORY DAMAGES: $500"
    assert body =~ "single payment of $900"
    assert body =~ "Santa Clara County Small Claims Court"
    assert body =~ "Acme Robocallers LLC"
    assert body =~ "123 Main St"
    assert body =~ "Limited time offer"
    assert body =~ "Exhibit A"
    refute body =~ "willful and knowing"
  end

  test "render/4 includes willful paragraph and damages after STOP date" do
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

    body = LetterDraft.render(case, [before_stop, after_stop], [])

    assert body =~ "willful and knowing"
    assert body =~ "June 1, 2026"
    assert body =~ "1 Standard Violations × $500 = $500"
    assert body =~ "1 Willful Violations × $1,500 = $1500"
    assert body =~ "TOTAL STATUTORY DAMAGES: $2000"
  end
end

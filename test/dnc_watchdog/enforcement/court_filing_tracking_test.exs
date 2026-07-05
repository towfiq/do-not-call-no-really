defmodule DncWatchdog.Enforcement.CourtFilingTrackingTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  import DncWatchdog.EnforcementFixtures

  test "count_high_small_claims_filings/2 counts recorded small claims filings over $2,500" do
    year = Date.utc_today().year

    case_a =
      case_fixture(%{company_name: "A"})
      |> then(fn c ->
        {:ok, c} =
          Enforcement.record_court_filing(c, %{
            court_filed_at: Date.new!(year, 3, 1),
            court_filed_venue: "small_claims",
            court_filed_amount: Decimal.new("5000")
          })

        c
      end)

    _case_b =
      case_fixture(%{company_name: "B"})
      |> then(fn c ->
        {:ok, _} =
          Enforcement.record_court_filing(c, %{
            court_filed_at: Date.new!(year, 4, 1),
            court_filed_venue: "small_claims",
            court_filed_amount: Decimal.new("2500")
          })

        c
      end)

    assert Enforcement.count_high_small_claims_filings(year) == 1

    case_c = case_fixture(%{company_name: "C"})
    communication_fixture(%{case_id: case_c.id, violation_status: "violation"})
    limits_c = Enforcement.assess_case_filing_limits(case_c)
    assert limits_c.small_claims_high_filings_this_year == 1
    assert limits_c.small_claims_high_filings_remaining == 1

    limits_a = Enforcement.assess_case_filing_limits(case_a)
    assert limits_a.small_claims_high_filings_this_year == 0
    assert limits_a.small_claims_high_filings_remaining == 2
  end

  test "workflow advances through litigation steps" do
    case =
      case_fixture(%{
        workflow_step: "litigation_draft",
        letter_draft: "Demand letter",
        court_filing_draft: "Small claims packet"
      })

    communication_fixture(%{case_id: case.id, violation_status: "violation"})

    assert {:ok, ready} = Enforcement.advance_case_workflow(case)
    assert ready.workflow_step == "ready_to_file"

    assert {:error, messages} = Enforcement.advance_case_workflow(ready)
    assert Enum.any?(messages, &String.contains?(&1, "court filing"))

    {:ok, ready} =
      Enforcement.record_court_filing(ready, %{
        court_filed_at: Date.utc_today(),
        court_filed_venue: "small_claims",
        court_filed_amount: Decimal.new("1500")
      })

    assert {:ok, filed} = Enforcement.advance_case_workflow(ready)
    assert filed.workflow_step == "filed"
    assert filed.status == "filed"
  end
end

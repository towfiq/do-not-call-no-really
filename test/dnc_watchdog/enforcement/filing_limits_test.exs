defmodule DncWatchdog.Enforcement.FilingLimitsTest do
  use ExUnit.Case, async: true

  alias DncWatchdog.Enforcement.FilingLimits

  test "assess/2 for case within small claims limits" do
    assessment = FilingLimits.assess(3, high_small_claims_filings_this_year: 0)

    assert assessment.violation_count == 3
    assert Decimal.equal?(assessment.total_damages, Decimal.new("4500"))
    assert Decimal.equal?(assessment.small_claims_claim_amount, Decimal.new("4500"))
    refute assessment.exceeds_small_claims_amount_cap
    assert assessment.can_file_small_claims
    assert assessment.recommended_venue == "small_claims"
    assert assessment.small_claims_high_filings_remaining == 2
  end

  test "assess/2 caps small claims amount at $12,500" do
    assessment = FilingLimits.assess(10, high_small_claims_filings_this_year: 0)

    assert Decimal.equal?(assessment.total_damages, Decimal.new("15000"))
    assert Decimal.equal?(assessment.small_claims_claim_amount, Decimal.new("12500"))
    assert assessment.exceeds_small_claims_amount_cap
    assert assessment.recommended_venue == "limited_civil"
    assert Enum.any?(assessment.warnings, &String.contains?(&1, "12500"))
  end

  test "assess/2 blocks third small claims filing over $2,500 in a year" do
    assessment = FilingLimits.assess(2, high_small_claims_filings_this_year: 2)

    refute assessment.can_file_small_claims
    assert assessment.recommended_venue == "limited_civil"
    assert Enum.any?(assessment.warnings, &String.contains?(&1, "CCP § 116.231"))
  end

  test "assess/2 recommends unlimited civil above $35,000" do
    assessment = FilingLimits.assess(24, high_small_claims_filings_this_year: 0)

    assert Decimal.equal?(assessment.total_damages, Decimal.new("36000"))
    assert assessment.recommended_venue == "unlimited_civil"
  end

  test "counts_toward_high_small_claims_limit?/2" do
    assert FilingLimits.counts_toward_high_small_claims_limit?("small_claims", Decimal.new("3000"))
    refute FilingLimits.counts_toward_high_small_claims_limit?("small_claims", Decimal.new("2500"))
    refute FilingLimits.counts_toward_high_small_claims_limit?("limited_civil", Decimal.new("10000"))
  end
end

defmodule DncWatchdog.Enforcement.FilingLimits do
  @moduledoc """
  California small-claims and civil court filing limit rules.

  Tracks per-violation trial damages ($1,500), the $12,500 small-claims cap,
  and the two-per-calendar-year limit for small-claims cases over $2,500
  (CCP § 116.231).
  """

  @per_violation_damages Decimal.new("1500.00")
  @small_claims_max Decimal.new("12500.00")
  @small_claims_high_threshold Decimal.new("2500.00")
  @max_high_small_claims_per_year 2
  @limited_civil_max Decimal.new("35000.00")

  @venues ~w(small_claims limited_civil unlimited_civil)

  def per_violation_damages, do: @per_violation_damages
  def small_claims_max, do: @small_claims_max
  def small_claims_high_threshold, do: @small_claims_high_threshold
  def max_high_small_claims_per_year, do: @max_high_small_claims_per_year
  def limited_civil_max, do: @limited_civil_max
  def venues, do: @venues

  @type assessment :: %{
          violation_count: non_neg_integer(),
          total_damages: Decimal.t(),
          small_claims_claim_amount: Decimal.t(),
          exceeds_small_claims_amount_cap: boolean(),
          small_claims_high_filings_this_year: non_neg_integer(),
          small_claims_high_filings_remaining: non_neg_integer(),
          needs_high_small_claims_slot: boolean(),
          can_file_small_claims: boolean(),
          recommended_venue: String.t(),
          recommended_venue_label: String.t(),
          warnings: [String.t()],
          calendar_year: integer()
        }

  @doc """
  Assesses filing limits for a case given violation count and how many
  small-claims filings over $2,500 were already recorded this calendar year.
  """
  @spec assess(non_neg_integer(), keyword()) :: assessment()
  def assess(violation_count, opts \\ []) when is_integer(violation_count) and violation_count >= 0 do
    year = Keyword.get(opts, :calendar_year, Date.utc_today().year)
    high_filings = Keyword.get(opts, :high_small_claims_filings_this_year, 0)

    total_damages = Decimal.mult(@per_violation_damages, Decimal.new(violation_count))
    small_claims_claim_amount = cap_at_small_claims_max(total_damages)
    exceeds_amount_cap = Decimal.compare(total_damages, @small_claims_max) == :gt

    needs_high_slot =
      Decimal.compare(small_claims_claim_amount, @small_claims_high_threshold) == :gt

    high_remaining = max(@max_high_small_claims_per_year - high_filings, 0)
    can_file_small_claims = !needs_high_slot || high_remaining > 0

    recommended_venue =
      recommend_venue(total_damages, can_file_small_claims, exceeds_amount_cap)

    warnings =
      build_warnings(
        total_damages,
        small_claims_claim_amount,
        exceeds_amount_cap,
        needs_high_slot,
        high_filings,
        high_remaining,
        can_file_small_claims,
        recommended_venue,
        year
      )

    %{
      violation_count: violation_count,
      total_damages: total_damages,
      small_claims_claim_amount: small_claims_claim_amount,
      exceeds_small_claims_amount_cap: exceeds_amount_cap,
      small_claims_high_filings_this_year: high_filings,
      small_claims_high_filings_remaining: high_remaining,
      needs_high_small_claims_slot: needs_high_slot,
      can_file_small_claims: can_file_small_claims,
      recommended_venue: recommended_venue,
      recommended_venue_label: venue_label(recommended_venue),
      warnings: warnings,
      calendar_year: year
    }
  end

  @doc """
  Returns true when a recorded filing counts toward the annual >$2,500 small-claims limit.
  """
  def counts_toward_high_small_claims_limit?("small_claims", %Decimal{} = amount) do
    Decimal.compare(amount, @small_claims_high_threshold) == :gt
  end

  def counts_toward_high_small_claims_limit?(_, _), do: false

  def venue_label("small_claims"), do: "Small Claims Court"
  def venue_label("limited_civil"), do: "Limited Civil (Superior Court)"
  def venue_label("unlimited_civil"), do: "Unlimited Civil (Superior Court)"
  def venue_label(other), do: other

  @doc """
  Like `assess/2` but always recommends a civil court track for complaint drafting.
  """
  def civil_assess(violation_count, opts \\ []) when is_integer(violation_count) and violation_count >= 0 do
    limits = assess(violation_count, opts)
    venue = civil_venue_for_amount(limits.total_damages)

    %{limits | recommended_venue: venue, recommended_venue_label: venue_label(venue)}
  end

  defp recommend_venue(total_damages, can_file_small_claims, exceeds_amount_cap) do
    cond do
      !can_file_small_claims ->
        civil_venue_for_amount(total_damages)

      exceeds_amount_cap ->
        civil_venue_for_amount(total_damages)

      true ->
        "small_claims"
    end
  end

  defp civil_venue_for_amount(total_damages) do
    if Decimal.compare(total_damages, @limited_civil_max) == :gt do
      "unlimited_civil"
    else
      "limited_civil"
    end
  end

  defp cap_at_small_claims_max(total) do
    if Decimal.compare(total, @small_claims_max) == :gt do
      @small_claims_max
    else
      total
    end
  end

  defp build_warnings(
         total,
         sc_amount,
         exceeds_cap,
         needs_high_slot,
         high_filings,
         high_remaining,
         can_sc,
         recommended,
         year
       ) do
    money = &format_money/1

    warnings = []

    warnings =
      if exceeds_cap do
        [
          "Total damages #{money.(total)} exceed the California small claims cap of #{money.(@small_claims_max)}. " <>
            "Small claims can only recover #{money.(sc_amount)}; use #{venue_label(recommended)} for the full amount."
          | warnings
        ]
      else
        warnings
      end

    warnings =
      if needs_high_slot && can_sc do
        [
          "This case would use 1 of your #{@max_high_small_claims_per_year} small-claims filings over #{money.(@small_claims_high_threshold)} in #{year} " <>
            "(#{high_remaining} slot(s) remaining after this filing)."
          | warnings
        ]
      else
        warnings
      end

    warnings =
      if needs_high_slot && !can_sc do
        [
          "You have already filed #{high_filings} small-claims case(s) over #{money.(@small_claims_high_threshold)} in #{year} " <>
            "(CCP § 116.231 limit: #{@max_high_small_claims_per_year} per year). File in #{venue_label(recommended)} instead."
          | warnings
        ]
      else
        warnings
      end

    warnings =
      if recommended != "small_claims" && !exceeds_cap && !needs_high_slot do
        warnings
      else
        warnings
      end

    Enum.reverse(warnings)
  end

  defp format_money(%Decimal{} = amount) do
    amount
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
    |> then(&"$#{&1}")
  end
end

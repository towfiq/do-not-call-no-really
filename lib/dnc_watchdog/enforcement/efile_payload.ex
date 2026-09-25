defmodule DncWatchdog.Enforcement.EfilePayload do
  @moduledoc """
  Builds a JSON payload the Chrome helper uses to fill Odyssey eFileCA
  up to review. The helper never submits or pays.
  """

  alias DncWatchdog.Enforcement.Case
  alias DncWatchdog.Enforcement.ClaimantProfile
  alias DncWatchdog.Enforcement.FilingLimits
  alias DncWatchdog.Enforcement.LegalEntity
  alias DncWatchdog.Enforcement.OfficialForms
  alias DncWatchdog.Enforcement.PdfForms

  @portal_url "https://california.tylertech.cloud/OfsEfsp/ui/landing"
  @court_name "Superior Court of California, County of Santa Clara"
  # Odyssey lists one civil location for the county, covering small claims too.
  @location_hints ["Santa Clara - Civil", "Santa Clara"]
  @limited_civil_threshold Decimal.new(10_000)

  @state_zip ~r/\s*(?<state>[A-Za-z]{2})\s+(?<zip>\d{5}(?:-\d{4})?)\s*\z/

  def portal_url, do: @portal_url

  @doc """
  Map a case into eFileCA wizard hints: court, parties, filing codes, documents.
  """
  def build(%Case{} = case_record, opts \\ []) do
    profile = Keyword.get(opts, :claimant_profile) || %ClaimantProfile{}
    origin = Keyword.get(opts, :origin, "")
    limits = Keyword.get(opts, :filing_limits) || FilingLimits.assess(0)
    venue = limits.recommended_venue

    plaintiff = plaintiff_party(case_record, profile)
    defendant = defendant_party(case_record)
    claim_amount = claim_amount(venue, limits)
    codes = venue_codes(venue, claim_amount)

    %{
      provider: "Odyssey eFileCA",
      portal_url: @portal_url,
      stop_before_submit: true,
      case_id: case_record.id,
      court: %{
        name: @court_name,
        location_hints: @location_hints
      },
      venue: venue,
      venue_label: FilingLimits.venue_label(venue),
      category_hints: codes.category_hints,
      case_type_hints: codes.case_type_hints,
      filing_code_hints: codes.filing_code_hints,
      filing_description: codes.filing_description,
      comments_to_court: comments_to_court(case_record, limits),
      client_reference: "DNC-#{case_record.id}",
      claim_amount: decimal_string(claim_amount),
      lead_attorney_hints: ["Pro Se", "Self Represented", "Self-Represented"],
      plaintiff: plaintiff,
      defendant: defendant,
      documents: documents(case_record, venue, origin, claim_amount),
      instructions: instructions(venue, limits)
    }
  end

  @doc false
  def parse_address(nil), do: empty_address()
  def parse_address(""), do: empty_address()

  def parse_address(text) when is_binary(text) do
    lines =
      text
      |> String.replace("\r\n", "\n")
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    parse_address_lines(lines)
  end

  @doc false
  def split_person_name(nil), do: %{first_name: nil, last_name: nil}

  def split_person_name(name) when is_binary(name) do
    name = String.trim(name)

    case String.split(name, ~r/\s+/, parts: 2) do
      [first, last] -> %{first_name: first, last_name: last}
      [first] -> %{first_name: first, last_name: first}
      _ -> %{first_name: name, last_name: name}
    end
  end

  defp plaintiff_party(case_record, profile) do
    name =
      ClaimantProfile.resolve(
        :name,
        nil,
        case_record.claimant_name,
        profile
      )

    address_text =
      ClaimantProfile.resolve(
        :address,
        nil,
        case_record.claimant_address,
        profile
      )

    phone =
      ClaimantProfile.resolve(
        :phone,
        nil,
        case_record.claimant_phone,
        profile
      )

    email =
      ClaimantProfile.resolve(
        :email,
        nil,
        case_record.claimant_email,
        profile
      )

    names = split_person_name(present(name))
    address = Map.put(parse_address(present(address_text)), :country_hints, ["United States"])

    %{
      role: "Plaintiff",
      party_type_hints: ["Plaintiff"],
      is_this_party: true,
      is_business: false,
      name: present(name),
      first_name: names.first_name,
      last_name: names.last_name,
      organization_name: nil,
      email: present(email),
      phone: present(phone),
      address: address
    }
  end

  defp defendant_party(case_record) do
    entity = case_record.legal_entity
    name = defendant_name(entity, case_record)
    business? = business_defendant?(entity, name)
    address = defendant_address(entity)
    names = if business?, do: %{first_name: nil, last_name: nil}, else: split_person_name(name)

    phone =
      case entity do
        %LegalEntity{phone: phone} when phone not in [nil, ""] -> present(phone)
        _ -> nil
      end

    contact = defendant_contact(entity)

    %{
      role: "Defendant",
      party_type_hints: ["Defendant"],
      is_this_party: false,
      is_business: business?,
      name: name,
      first_name: names.first_name,
      last_name: names.last_name,
      organization_name: if(business?, do: name),
      email: nil,
      phone: phone,
      address: address,
      contact: contact
    }
  end

  defp defendant_contact(entity) do
    case LegalEntity.service_agent(entity) do
      nil ->
        nil

      agent ->
        names = split_person_name(agent.name)
        business? = business_name?(agent.name)

        %{
          role: "Registered Agent",
          title: agent.title,
          is_business: business?,
          name: agent.name,
          first_name: names.first_name,
          last_name: names.last_name,
          organization_name: if(business?, do: agent.name),
          phone: present(agent.phone),
          address: %{
            street: present(agent.street),
            city: present(agent.city),
            state: present(format_region(agent.state)),
            zip: present(agent.zip),
            country: present(agent.country)
          }
        }
    end
  end

  defp business_name?(name) do
    Regex.match?(
      ~r/\b(llc|l\.l\.c|inc|incorporated|corp|corporation|company|co\.|llp|l\.l\.p|lp|ltd|system)\b/i,
      name || ""
    )
  end

  defp defendant_name(%LegalEntity{legal_name: name}, _case) when name not in [nil, ""], do: name
  defp defendant_name(_, %Case{company_name: name}) when name not in [nil, ""], do: name
  defp defendant_name(_, _), do: nil

  defp business_defendant?(%LegalEntity{entity_type: "individual"}, _name), do: false

  defp business_defendant?(%LegalEntity{entity_type: type}, _name)
       when type in ["company", "unknown"],
       do: true

  defp business_defendant?(_, name) when is_binary(name) do
    Regex.match?(
      ~r/\b(llc|l\.l\.c|inc|incorporated|corp|corporation|company|co\.|llp|l\.l\.p|lp|ltd)\b/i,
      name
    )
  end

  defp business_defendant?(_, _), do: true

  defp defendant_address(%LegalEntity{} = entity) do
    %{
      street: present(entity.street),
      city: present(entity.city),
      state: present(format_region(entity.state)),
      zip: present(entity.zip),
      country: LegalEntity.country_label(entity),
      country_hints: country_hints(entity)
    }
  end

  defp defendant_address(_), do: empty_address()

  defp format_region(nil), do: nil

  defp format_region(state) when is_binary(state) do
    trimmed = String.trim(state)
    if String.length(trimmed) == 2, do: String.upcase(trimmed), else: trimmed
  end

  defp country_hints(entity) do
    case LegalEntity.normalize_country(entity.country) do
      "US" -> ["United States", "USA", "US"]
      "GB" -> ["United Kingdom", "UK", "Great Britain", "England", "GB"]
      _ -> [LegalEntity.country_label(entity)]
    end
  end

  defp documents(case_record, venue, origin, claim_amount) do
    (official_documents(case_record, venue, origin) ++
       narrative_documents(case_record, venue, origin, claim_amount))
    |> Enum.sort_by(&(!&1.lead?))
  end

  defp official_documents(case_record, venue, origin) do
    venue
    |> OfficialForms.for_venue()
    |> Enum.filter(&PdfForms.template_available?(&1.code))
    |> Enum.map(fn spec ->
      %{
        label: "#{spec.code} — #{spec.title}",
        url: "#{origin}/cases/#{case_record.id}/forms/#{spec.filename}",
        lead?: spec.lead?,
        filing_code_hints: spec.filing_code_hints,
        description: "Filled #{spec.code} (#{spec.title})",
        attach?: true
      }
    end)
  end

  defp narrative_documents(case_record, venue, origin, claim_amount) do
    small_claims? = venue == "small_claims"

    [
      {case_record.court_filing_draft, "Small claims packet", "court_filing.pdf",
       "Statement of facts, declaration, damages worksheet, and exhibits", small_claims?},
      {case_record.civil_complaint_draft, "Civil complaint packet", "civil_complaint.pdf",
       "Civil complaint with declaration and exhibits", !small_claims?}
    ]
    |> Enum.filter(fn {draft, _label, _path, _description, relevant?} ->
      relevant? and draft not in [nil, ""]
    end)
    |> Enum.map(fn {_draft, label, path, description, _relevant?} ->
      %{
        label: label,
        url: "#{origin}/cases/#{case_record.id}/#{path}",
        # The official form is the lead document; the narrative rides behind it.
        lead?: !small_claims?,
        filing_code_hints: venue_codes(venue, claim_amount).filing_code_hints,
        description: description,
        attach?: true
      }
    end)
  end

  # Santa Clara splits its civil categories and complaint filing codes by amount,
  # and the helper matches these labels exactly, so pick the right pair here.
  defp venue_codes("small_claims", _amount) do
    %{
      category_hints: ["Civil - Small Claims", "Small Claims"],
      case_type_hints: ["Small Claims", "Plaintiff's Claim"],
      filing_code_hints: ["Plaintiff's Claim", "SC-100", "Complaint"],
      filing_description:
        "Plaintiff's Claim and ORDER to Go to Small Claims Court — TCPA / National Do Not Call"
    }
  end

  defp venue_codes("limited_civil", amount) do
    if over_limited_threshold?(amount) do
      %{
        category_hints: ["Civil - Limited $10,001 - $35,000", "Civil - Limited"],
        case_type_hints: ["Other Complaint", "Other Civil"],
        filing_code_hints: ["Complaint (Limited): Over $10K", "Complaint (Limited)"],
        filing_description: "Complaint for TCPA / National Do Not Call violations (limited civil)"
      }
    else
      %{
        category_hints: ["Civil - Limited Under $10,000", "Civil - Limited"],
        case_type_hints: ["Other Complaint", "Other Civil"],
        filing_code_hints: ["Complaint (Limited): Up to $10K", "Complaint (Limited)"],
        filing_description: "Complaint for TCPA / National Do Not Call violations (limited civil)"
      }
    end
  end

  defp venue_codes(_unlimited_civil, _amount) do
    %{
      category_hints: ["Civil - Unlimited", "Civil Unlimited", "Unlimited Civil"],
      case_type_hints: ["Other Complaint", "Other Civil"],
      filing_code_hints: ["Complaint (Unlimited) (Fee Applies)", "Complaint (Unlimited)"],
      filing_description: "Complaint for TCPA / National Do Not Call violations (unlimited civil)"
    }
  end

  defp over_limited_threshold?(nil), do: true

  defp over_limited_threshold?(amount),
    do: Decimal.compare(amount, @limited_civil_threshold) == :gt

  defp comments_to_court(case_record, limits) do
    defendant = defendant_name(case_record.legal_entity, case_record) || "defendant"

    "Self-represented plaintiff. TCPA / National Do Not Call claim against #{defendant}. " <>
      "#{limits.violation_count} alleged violations; amount claimed $#{decimal_string(claim_amount(limits.recommended_venue, limits))}."
  end

  defp claim_amount("small_claims", limits), do: limits.small_claims_claim_amount
  defp claim_amount(_, limits), do: limits.total_damages

  defp instructions(venue, limits) do
    [
      "Register as Individual (self-represented) if you do not already have an Odyssey eFileCA login.",
      "Add a payment account in Odyssey before the first filing. This portal has no extra EFSP markup — you pay court fees plus the eFileCA technology fee.",
      "Recommended venue: #{FilingLimits.venue_label(venue)}.",
      "The helper fills location, case type, parties, and filing description, then attaches the filled court forms on the Documents step (lead document first).",
      "Stop at Review. Do not let the helper click Submit — check parties, codes, fees, and PDFs, then submit yourself."
    ] ++ Enum.map(limits.warnings, &("WARNING: " <> &1))
  end

  defp parse_address_lines([]), do: empty_address()

  defp parse_address_lines(lines) do
    {street_lines, [last]} = Enum.split(lines, -1)

    case extract_state_zip(last) do
      {:ok, remainder, state, zip} ->
        {street, city} = split_street_city(street_lines, remainder)

        %{
          street: present(street),
          city: present(city),
          state: state,
          zip: zip
        }

      :error ->
        %{empty_address() | street: Enum.join(lines, ", ")}
    end
  end

  defp extract_state_zip(text) do
    case Regex.named_captures(@state_zip, text) do
      %{"state" => state, "zip" => zip} ->
        remainder =
          text
          |> String.replace(@state_zip, "")
          |> String.trim()
          |> String.trim_trailing(",")
          |> String.trim()

        {:ok, remainder, String.upcase(state), zip}

      _ ->
        :error
    end
  end

  defp split_street_city(street_lines, remainder) do
    cond do
      street_lines != [] ->
        {Enum.join(street_lines, ", "), remainder}

      remainder in [nil, ""] ->
        {nil, nil}

      String.contains?(remainder, ",") ->
        [city | rest] =
          remainder
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reverse()

        {rest |> Enum.reverse() |> Enum.join(", "), city}

      true ->
        {nil, remainder}
    end
  end

  defp empty_address,
    do: %{street: nil, city: nil, state: nil, zip: nil, country: nil, country_hints: []}

  defp present(value) when value in [nil, ""], do: nil
  defp present(value) when is_binary(value), do: String.trim(value)
  defp present(value), do: value

  defp decimal_string(%Decimal{} = amount) do
    amount |> Decimal.round(2) |> Decimal.to_string(:normal)
  end

  defp decimal_string(_), do: nil
end

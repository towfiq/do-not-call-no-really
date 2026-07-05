defmodule DncWatchdog.Enforcement.CourtFilingDraft do
  @moduledoc """
  Builds small-claims filing drafts for Santa Clara County, California.

  Produces a filing packet you can review and use to complete official court
  forms (SC-100 and related). Download blank forms from
  https://courts.ca.gov/find-court-forms and file with the Santa Clara County
  Superior Court Small Claims Division.
  """

  alias DncWatchdog.Enforcement.Case
  alias DncWatchdog.Enforcement.ClaimantProfile
  alias DncWatchdog.Enforcement.EvidenceAttachment
  alias DncWatchdog.Enforcement.LegalEntity
  alias DncWatchdog.Enforcement.FilingLimits

  @court_name "Superior Court of California, County of Santa Clara"
  @court_division "Small Claims Division"
  @court_address "191 North First Street, San Jose, CA 95113"
  @court_website "https://santaclara.courts.ca.gov"
  @small_claims_url "https://santaclara.courts.ca.gov/divisions/small-claims-division"
  @forms_url "https://courts.ca.gov/find-court-forms"
  @default_county "Santa Clara County"

  @doc """
  Renders a Santa Clara County small-claims filing packet from case evidence.
  """
  def render(%Case{} = case, violations, attachments, opts \\ []) do
    profile = Keyword.get(opts, :claimant_profile)
    limits = Keyword.get(opts, :filing_limits) || FilingLimits.assess(length(violations))
    facts = build_facts(case, violations, attachments, profile, limits, opts)

    """
    #{header(facts)}

    #{filing_checklist()}

    #{sc100_worksheet(facts)}

    #{statement_of_facts(facts)}

    #{declaration(facts)}

    #{damages_worksheet(facts)}

    #{exhibit_index(facts, attachments)}

    #{violation_schedule(facts)}

    #{proof_of_service_notes(facts)}
    """
    |> String.trim()
  end

  defp build_facts(case, violations, attachments, profile, limits, opts) do
    claimant_name =
      ClaimantProfile.resolve(
        :name,
        Keyword.get(opts, :claimant_name),
        case.claimant_name,
        profile
      )

    claimant_address =
      ClaimantProfile.resolve(
        :address,
        Keyword.get(opts, :claimant_address),
        case.claimant_address,
        profile
      )

    claimant_phone =
      ClaimantProfile.resolve(
        :phone,
        Keyword.get(opts, :claimant_phone),
        case.claimant_phone,
        profile
      )

    claimant_email =
      ClaimantProfile.resolve(
        :email,
        Keyword.get(opts, :claimant_email),
        case.claimant_email,
        profile
      )

    county =
      ClaimantProfile.resolve(
        :small_claims_county,
        Keyword.get(opts, :small_claims_county),
        case.small_claims_county,
        profile
      )

    county = if county in [nil, "", "[Your County]"], do: @default_county, else: county

    dnc_date = dnc_date(case, opts, profile)
    stop_date = stop_contact_date(case, opts)
    entity = case.legal_entity
    defendant_name = defendant_name(entity, case)
    defendant_address = defendant_address(entity)

    sorted_violations = Enum.sort_by(violations, & &1.timestamp, NaiveDateTime)
    total_count = limits.violation_count
    total_statutory = limits.total_damages
    claim_amount = limits.small_claims_claim_amount
    capped? = limits.exceeds_small_claims_amount_cap

    {first_date, last_date} = violation_date_range(sorted_violations)
    channel_label = channel_label(sorted_violations)
    letter_date = format_date(Date.utc_today())

    %{
      case: case,
      claimant_name: claimant_name,
      claimant_address: claimant_address,
      claimant_phone: claimant_phone,
      claimant_email: claimant_email,
      county: county,
      dnc_date: dnc_date,
      stop_date: stop_date,
      defendant_name: defendant_name,
      defendant_address: defendant_address,
      sorted_violations: sorted_violations,
      total_count: total_count,
      total_statutory: total_statutory,
      claim_amount: claim_amount,
      capped?: capped?,
      limits: limits,
      first_date: first_date,
      last_date: last_date,
      channel_label: channel_label,
      letter_date: letter_date,
      attachments: attachments
    }
  end

  defp header(facts) do
    """
    SMALL CLAIMS FILING PACKET
    #{@court_name} — #{@court_division}
    #{facts.county}, California

    Case reference: DncWatchdog case #{facts.case.id}
    Prepared: #{facts.letter_date}

    IMPORTANT: This packet is generated software output, not legal advice. Review
    everything before filing. Complete official forms from #{@forms_url}. Confirm
    filing fees, hours, and procedures at #{@court_website}.
    Recommended venue: #{facts.limits.recommended_venue_label}.
    #{limits_summary(facts.limits)}
    """
    |> String.trim()
  end

  defp limits_summary(%{warnings: []}), do: ""

  defp limits_summary(%{warnings: warnings}) do
    warnings
    |> Enum.map(&("    WARNING: " <> &1))
    |> Enum.join("\n")
    |> then(&("\n\n" <> &1))
  end

  defp filing_checklist do
    """
    ================================================================================
    1. FILING CHECKLIST (Santa Clara County)
    ================================================================================

    Before you go to court:

    [ ] Download blank form SC-100 (Plaintiff's Claim and ORDER to Go to Small Claims Court)
        from #{@forms_url}
    [ ] Copy values from Section 2 (SC-100 Field Worksheet) into the official SC-100 PDF
    [ ] Print the Statement of Facts (Section 3) and Declaration (Section 4) to attach
    [ ] Print the Damages Worksheet (Section 5) and Violation Schedule (Section 7)
    [ ] Gather exhibits listed in Section 6; label each exhibit (Exhibit A, B, C, …)
    [ ] If you sent a demand letter, include it as an exhibit with USPS delivery proof
    [ ] Confirm your claim amount does not exceed the California small claims limit ($12,500
        for natural persons). Amounts above the limit are filed at $12,500.
    [ ] File at the Small Claims Division, #{@court_address}
    [ ] Pay the filing fee (check #{@small_claims_url} for current amount)
    [ ] After filing, serve the defendant with copies of your claim and court papers
        (see Section 8). Use form SC-104 or POS-040 for proof of service.
    [ ] Keep copies of everything you file and serve.

    Optional resources:
    - Santa Clara County Small Claims Division: #{@small_claims_url}
    - Santa Clara County small claims forms: https://santaclara.courts.ca.gov/self-help/self-help-topics/self-help-small-claims/small-claims-forms
    - Self-Help: California Courts small claims guide at https://selfhelp.courts.ca.gov/small-claims
    """
    |> String.trim()
  end

  defp sc100_worksheet(facts) do
    venue_line =
      "Santa Clara County (violations occurred by phone/text to plaintiff in this county; " <>
        "plaintiff resides in #{facts.county})"

    reason =
      "Unwanted telemarketing #{facts.channel_label} in violation of the Telephone Consumer " <>
        "Protection Act (47 U.S.C. § 227) and National Do Not Call Registry rules."

    """
    ================================================================================
    2. SC-100 FIELD WORKSHEET
    ================================================================================
    Copy these values into the official SC-100 PDF. Field numbers refer to the
    January 2024 revision of form SC-100.

    PLAINTIFF (person who was harmed — you):
      Name: #{facts.claimant_name}
      Street address: #{address_line(facts.claimant_address, 0)}
      City, State, Zip: #{address_line(facts.claimant_address, 1)}
      Phone: #{facts.claimant_phone}
      Email (optional): #{facts.claimant_email}

    DEFENDANT (person or company you are suing):
      Name: #{facts.defendant_name}
      Street address: #{defendant_street(facts.defendant_address)}
      City, State, Zip: #{defendant_city_state_zip(facts.defendant_address)}

    AMOUNT OF CLAIM (Item 5 on SC-100):
      #{format_money(facts.claim_amount)}

    REASON FOR CLAIM (Item 6 — brief summary for the form):
      #{reason}

    WHEN AND WHERE THE CLAIM AROSE (Item 7):
      Between #{facts.first_date} and #{facts.last_date}. Calls and texts to plaintiff's
      wireless number #{facts.claimant_phone} while plaintiff's number was on the National
      Do Not Call Registry (registered since #{facts.dnc_date}).

    VENUE — WHY YOU ARE FILING IN THIS COUNTY (Item 8):
      #{venue_line}

    ADDITIONAL DETAILS (attach separate pages as allowed by SC-100 instructions):
      Attach Sections 3–7 of this packet and labeled exhibits.
    """
    |> String.trim()
  end

  defp statement_of_facts(facts) do
    stop_detail =
      case facts.stop_date do
        %Date{} = date ->
          " On #{format_date(date)}, plaintiff demanded in writing that defendant stop all " <>
            "telemarketing contact; defendant continued contacting plaintiff afterward."

        _ ->
          ""
      end

    """
    ================================================================================
    3. PLAINTIFF'S CLAIM AND STATEMENT OF FACTS
    ================================================================================
    (Attach to SC-100 or file as a separate statement if permitted by the clerk.)

    PLAINTIFF: #{facts.claimant_name}
    DEFENDANT: #{facts.defendant_name}
    AMOUNT SOUGHT: #{format_money(facts.claim_amount)}

    I. PARTIES

    1. Plaintiff #{facts.claimant_name} ("Plaintiff") is an individual residing at
       #{single_line_address(facts.claimant_address)}. Plaintiff's wireless telephone number
       is #{facts.claimant_phone}.

    2. Defendant #{facts.defendant_name} ("Defendant") is the business entity that placed
       the telemarketing #{facts.channel_label} described below and may be served at
       #{single_line_address(facts.defendant_address)}.

    II. JURISDICTION AND VENUE

    3. This Court has jurisdiction because the amount claimed does not exceed the limit for
       small claims court and the claim arises under federal telecommunications law with
       damages recoverable in state court.

    4. Venue is proper in #{facts.county} because Plaintiff resides in this county and
       received the unauthorized contacts here.

    III. FACTUAL ALLEGATIONS

    5. Plaintiff's phone number has been registered on the National Do Not Call Registry
       since #{facts.dnc_date}.

    6. Defendant placed #{facts.total_count} unauthorized telemarketing #{facts.channel_label}
       to Plaintiff's wireless number between #{facts.first_date} and #{facts.last_date}.

    7. Plaintiff did not provide prior express consent for these marketing #{facts.channel_label}.

    8. Plaintiff notified defendant in writing that continued contact would result in a claim
       for the maximum statutory damages of #{format_money(FilingLimits.per_violation_damages())} per violation
       at trial, consistent with plaintiff's demand letter.#{stop_detail}

    9. Each unauthorized contact was willful or knowing. Plaintiff seeks
       #{format_money(FilingLimits.per_violation_damages())} per violation under 47 U.S.C. § 227(b)(3).

    IV. CAUSES OF ACTION

    10. Violation of the Telephone Consumer Protection Act, 47 U.S.C. § 227(b)(1)(A)(iii)
        (calls/texts to wireless numbers using an automatic telephone dialing system or
        prerecorded/artificial voice without consent).

    11. Violation of National Do Not Call Registry provisions, 47 U.S.C. § 227(c) and
        47 C.F.R. § 64.1200 (telemarketing calls to numbers on the Registry).

    V. DAMAGES

    12. The TCPA provides a private right of action trebled to #{format_money(FilingLimits.per_violation_damages())}
        per violation for willful or knowing conduct. Plaintiff's damages are:

        #{damages_lines(facts)}

    VI. PRAYER FOR RELIEF

    13. Plaintiff requests judgment against Defendant in the amount of
        #{format_money(facts.claim_amount)}, plus court costs and such other relief as the
        Court deems just.
    """
    |> String.trim()
  end

  defp declaration(facts) do
    """
    ================================================================================
    4. DECLARATION IN SUPPORT OF CLAIM
    ================================================================================

    I, #{facts.claimant_name}, declare:

    1. I am the Plaintiff in this action. I have read the Statement of Facts above and
       know the contents are true of my own knowledge except as to matters stated on
       information and belief, and as to those matters I believe them to be true.

    2. The contact records, screenshots, and other exhibits attached to this claim are
       true and accurate copies or summaries of unauthorized #{facts.channel_label} I received
       from or on behalf of Defendant #{facts.defendant_name}.

    3. My phone number #{facts.claimant_phone} has been on the National Do Not Call Registry
       since #{facts.dnc_date}.

    I declare under penalty of perjury under the laws of the State of California that the
    foregoing is true and correct.

    Executed on #{facts.letter_date} at #{facts.county}, California.


    _________________________________
    #{facts.claimant_name}
    """
    |> String.trim()
  end

  defp damages_worksheet(facts) do
    cap_note =
      if facts.capped? do
        """

        Amount filed in small claims court (California limit): #{format_money(facts.claim_amount)}
        """
      else
        ""
      end

    """
    ================================================================================
    5. DAMAGES WORKSHEET
    ================================================================================

    Willful/knowing violations (#{format_money(FilingLimits.per_violation_damages())} each):
      Count: #{facts.total_count}
      Subtotal: #{format_money(facts.total_statutory)}

    TOTAL DAMAGES AT TRIAL RATE: #{format_money(facts.total_statutory)}
    #{cap_note}
    """
    |> String.trim()
  end

  defp exhibit_index(facts, attachments) do
    demand_exhibit =
      if facts.case.letter_draft not in [nil, ""] do
        ["- Exhibit A: Demand letter sent to defendant"]
      else
        []
      end

    tracking_exhibit =
      if facts.case.mail_tracking_number not in [nil, ""] do
        status =
          facts.case.mail_tracking_summary || facts.case.mail_delivery_status || "see tracking"

        [
          "- Exhibit B: USPS certified mail tracking (#{facts.case.mail_tracking_number}) — #{status}"
        ]
      else
        []
      end

    start_idx = length(demand_exhibit) + length(tracking_exhibit) + 1

    attachment_lines =
      attachments
      |> Enum.with_index(start_idx)
      |> Enum.map(fn {%EvidenceAttachment{} = att, idx} ->
        label = att.caption || att.filename
        "- Exhibit #{exhibit_letter(idx)}: #{label}"
      end)

    lines = demand_exhibit ++ tracking_exhibit ++ attachment_lines

    body =
      if lines == [] do
        "(No exhibits yet — upload evidence attachments and generate a demand letter before filing.)"
      else
        Enum.join(lines, "\n")
      end

    """
    ================================================================================
    6. EXHIBIT INDEX
    ================================================================================

    Label each physical or PDF exhibit before filing. Suggested index:

    #{body}
    """
    |> String.trim()
  end

  defp violation_schedule(facts) do
    rows =
      facts.sorted_violations
      |> Enum.with_index(1)
      |> Enum.map(fn {comm, idx} ->
        time = format_timestamp(comm.timestamp)
        body = String.slice(comm.body || "", 0, 60)

        "| #{idx} | #{time} | #{comm.channel} | #{comm.from_number} | #{format_money(FilingLimits.per_violation_damages())} | #{body} |"
      end)
      |> Enum.join("\n")

    table =
      if rows == "" do
        "(No violations marked — mark communications as violations before generating a filing draft.)"
      else
        """
        | # | Date & Time | Channel | From | Damages | Message (excerpt) |
        | --- | --- | --- | --- | --- | --- |
        #{rows}
        """
        |> String.trim()
      end

    """
    ================================================================================
    7. VIOLATION SCHEDULE
    ================================================================================

    #{table}
    """
    |> String.trim()
  end

  defp proof_of_service_notes(facts) do
    """
    ================================================================================
    8. SERVICE OF PROCESS — REMINDER
    ================================================================================

    After the clerk accepts your claim, you must properly serve Defendant:

      Defendant: #{facts.defendant_name}
      Address:   #{single_line_address(facts.defendant_address)}

    - You cannot serve the papers yourself. Use someone 18 or older who is not a party.
    - Complete proof of service (form SC-104 or POS-040) and file it with the court.
    - Serve copies of: SC-100, Statement of Facts, Declaration, exhibits, and the court's
      claim of defendant form if provided by the clerk.

    See #{@forms_url} for SC-104 (Defendant's Claim) and POS-040 (Proof of Service).
    """
    |> String.trim()
  end

  defp damages_lines(facts) do
    lines = [
      "#{facts.total_count} violations × #{format_money(FilingLimits.per_violation_damages())} = #{format_money(facts.total_statutory)}"
    ]

    if facts.capped? do
      lines ++
        [
          "Amount claimed in small claims court: #{format_money(facts.claim_amount)} (California limit)"
        ]
    else
      lines
    end
    |> Enum.map_join("\n       ", & &1)
  end

  defp defendant_name(%LegalEntity{legal_name: name}, _case) when name not in [nil, ""], do: name
  defp defendant_name(_, %Case{company_name: name}) when name not in [nil, ""], do: name
  defp defendant_name(_, _), do: "[Defendant Name]"

  defp defendant_address(%LegalEntity{} = entity) do
    city_state_zip =
      [entity.city, entity.state, entity.zip]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(", ")

    [entity.street, city_state_zip]
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp defendant_address(_), do: ["[Defendant Street Address]", "[City, State Zip]"]

  defp defendant_street([street | _]) when street not in [nil, ""], do: street
  defp defendant_street(_), do: "[Defendant Street Address]"

  defp defendant_city_state_zip([_, city_state | _]), do: city_state
  defp defendant_city_state_zip([city_state]), do: city_state
  defp defendant_city_state_zip(_), do: "[City, State Zip]"

  defp address_line(address, 0) when is_binary(address) do
    address |> String.split("\n") |> List.first() || address
  end

  defp address_line(address, 1) when is_binary(address) do
    address
    |> String.split("\n")
    |> Enum.drop(1)
    |> Enum.join(", ")
    |> case do
      "" -> "[City, State Zip]"
      line -> line
    end
  end

  defp address_line(_, _), do: "[Address]"

  defp single_line_address(lines) when is_list(lines), do: Enum.join(lines, ", ")

  defp single_line_address(address) when is_binary(address),
    do: String.replace(address, "\n", ", ")

  defp dnc_date(%Case{dnc_registration_date: %Date{} = date}, _opts, _profile),
    do: format_date(date)

  defp dnc_date(%Case{} = case, opts, profile) do
    case ClaimantProfile.resolve(
           :dnc_registration_date,
           Keyword.get(opts, :dnc_registration_date),
           case.dnc_registration_date,
           profile
         ) do
      %Date{} = date -> format_date(date)
      value -> value
    end
  end

  defp stop_contact_date(%Case{stop_contact_date: %Date{} = date}, _opts), do: date
  defp stop_contact_date(%Case{}, opts), do: Keyword.get(opts, :stop_contact_date)

  defp violation_date_range([]), do: {"[first violation date]", "[last violation date]"}

  defp violation_date_range(violations) do
    first = violations |> List.first() |> Map.fetch!(:timestamp) |> format_date()
    last = violations |> List.last() |> Map.fetch!(:timestamp) |> format_date()
    {first, last}
  end

  defp channel_label(violations) do
    channels = violations |> Enum.map(& &1.channel) |> Enum.uniq()
    has_calls = Enum.any?(channels, &call_channel?/1)
    has_texts = Enum.any?(channels, &text_channel?/1)

    case {has_calls, has_texts} do
      {true, true} -> "calls and text messages"
      {true, false} -> "calls"
      {false, true} -> "text messages"
      _ -> "calls and text messages"
    end
  end

  defp call_channel?(channel) when channel in ["call", "phone", "voice", "voicemail"], do: true
  defp call_channel?(_), do: false

  defp text_channel?(channel) when channel in ["sms", "text", "imessage", "message"], do: true
  defp text_channel?(_), do: false

  defp format_money(%Decimal{} = amount) do
    amount
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
    |> then(&"$#{&1}")
  end

  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%B %-d, %Y")
  defp format_date(%NaiveDateTime{} = dt), do: dt |> NaiveDateTime.to_date() |> format_date()
  defp format_date(value) when is_binary(value), do: value

  defp format_timestamp(%NaiveDateTime{} = dt) do
    dt |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_string()
  end

  defp format_timestamp(value), do: to_string(value)

  defp exhibit_letter(idx) when idx <= 26, do: <<?A + idx - 1>>
  defp exhibit_letter(idx), do: "Ex#{idx}"
end

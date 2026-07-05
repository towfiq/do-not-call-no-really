defmodule DncWatchdog.Enforcement.CivilComplaintDraft do
  @moduledoc """
  Builds limited/unlimited civil complaint drafts for Santa Clara County Superior Court.
  """

  alias DncWatchdog.Enforcement.Case
  alias DncWatchdog.Enforcement.ClaimantProfile
  alias DncWatchdog.Enforcement.EvidenceAttachment
  alias DncWatchdog.Enforcement.FilingLimits
  alias DncWatchdog.Enforcement.LegalEntity

  @court_name "Superior Court of California, County of Santa Clara"
  @court_address "191 North First Street, San Jose, CA 95113"
  @court_website "https://santaclara.courts.ca.gov"
  @civil_division_url "https://santaclara.courts.ca.gov/divisions/civil-division"
  @forms_url "https://courts.ca.gov/find-court-forms"
  @default_county "Santa Clara County"

  @doc """
  Renders a civil complaint filing packet for Santa Clara County.
  """
  def render(%Case{} = case, violations, attachments, opts \\ []) do
    profile = Keyword.get(opts, :claimant_profile)
    limits = Keyword.get(opts, :filing_limits) || FilingLimits.assess(length(violations))
    facts = build_facts(case, violations, attachments, profile, limits, opts)

    """
    #{header(facts)}

    #{filing_checklist(facts)}

    #{summons_worksheet(facts)}

    #{cover_sheet_worksheet(facts)}

    #{complaint(facts)}

    #{declaration(facts)}

    #{damages_worksheet(facts)}

    #{exhibit_index(facts, attachments)}

    #{violation_schedule(facts)}

    #{service_notes(facts)}
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
    {first_date, last_date} = violation_date_range(sorted_violations)
    channel_label = channel_label(sorted_violations)
    letter_date = format_date(Date.utc_today())
    civil_track = limits.recommended_venue

    %{
      case: case,
      limits: limits,
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
      total_count: limits.violation_count,
      total_damages: limits.total_damages,
      civil_track: civil_track,
      civil_track_label: FilingLimits.venue_label(civil_track),
      first_date: first_date,
      last_date: last_date,
      channel_label: channel_label,
      letter_date: letter_date,
      attachments: attachments
    }
  end

  defp header(facts) do
    """
    CIVIL COMPLAINT FILING PACKET
    #{@court_name} — #{facts.civil_track_label}
    #{facts.county}, California

    Case reference: DncWatchdog case #{facts.case.id}
    Prepared: #{facts.letter_date}
    Amount demanded: #{format_money(facts.total_damages)}

    IMPORTANT: Generated software output, not legal advice. Review before filing.
    File at #{@civil_division_url}. Download statewide forms at #{@forms_url}.
    #{limits_summary(facts.limits)}
    """
    |> String.trim()
  end

  defp limits_summary(limits) do
    lines =
      limits.warnings
      |> Enum.map(&("    WARNING: " <> &1))

    if lines == [] do
      ""
    else
      "\n\n" <> Enum.join(lines, "\n")
    end
  end

  defp filing_checklist(facts) do
    """
    ================================================================================
    1. FILING CHECKLIST (Santa Clara County Civil Division)
    ================================================================================

    Recommended track: #{facts.civil_track_label}

    [ ] Download Summons (SUM-100) and Civil Case Cover Sheet (CM-010) from #{@forms_url}
    [ ] Print the Complaint (Section 4) on 28-line pleading paper
    [ ] Submit blank Civil Lawsuit Notice (CV-5012) with your initial filing (Santa Clara local rule)
    [ ] File at Downtown Superior Court, #{@court_address}
    [ ] Pay the civil filing fee (or submit fee waiver FW-001) — see #{@court_website}
    [ ] Serve defendant with Summons + Complaint; file Proof of Service (POS-010)
    [ ] Keep copies of everything filed and served

    Self-represented parties may file on paper. Attorneys must e-file.
    """
    |> String.trim()
  end

  defp summons_worksheet(facts) do
    """
    ================================================================================
    2. SUMMONS (SUM-100) WORKSHEET
    ================================================================================

    Plaintiff: #{facts.claimant_name}
    Defendant: #{facts.defendant_name}
    Defendant address for service: #{single_line_address(facts.defendant_address)}

    Court: #{@court_name}
    Court address: #{@court_address}
    Case type: Civil — #{facts.civil_track_label}
    """
    |> String.trim()
  end

  defp cover_sheet_worksheet(facts) do
    """
    ================================================================================
    3. CIVIL CASE COVER SHEET (CM-010) WORKSHEET
    ================================================================================

    Plaintiff: #{facts.claimant_name}
    Defendant: #{facts.defendant_name}
    Type of case: Other civil complaint (TCPA / telemarketing)
    Amount demanded: #{format_money(facts.total_damages)}
    """
    |> String.trim()
  end

  defp complaint(facts) do
    stop_detail =
      case facts.stop_date do
        %Date{} = date ->
          " On #{format_date(date)}, plaintiff demanded in writing that defendant cease all contact; " <>
            "defendant continued thereafter."

        _ ->
          ""
      end

    """
    ================================================================================
    4. COMPLAINT
    ================================================================================
    (Print on 28-line pleading paper; attach to Summons when filing.)

    SUPERIOR COURT OF CALIFORNIA, COUNTY OF SANTA CLARA
    #{facts.civil_track_label}

    #{facts.claimant_name},                    Case No. _______________
          Plaintiff,

    vs.

    #{facts.defendant_name},
          Defendant.

    COMPLAINT FOR DAMAGES
    (Violation of Telephone Consumer Protection Act, 47 U.S.C. § 227)

    Plaintiff alleges:

    PARTIES

    1. Plaintiff #{facts.claimant_name} is an individual residing in #{facts.county},
       California at #{single_line_address(facts.claimant_address)}. Plaintiff's wireless
       telephone number is #{facts.claimant_phone}.

    2. Defendant #{facts.defendant_name} is the business entity that placed the
       unauthorized telemarketing #{facts.channel_label} alleged herein and may be served at
       #{single_line_address(facts.defendant_address)}.

    JURISDICTION AND VENUE

    3. This Court has jurisdiction. The amount in controversy exceeds the small claims limit
       and this action is properly brought in the #{facts.civil_track_label}.

    4. Venue is proper in #{facts.county} because Plaintiff resides here and received the
       unauthorized contacts in this county.

    FACTS

    5. Plaintiff's telephone number has been registered on the National Do Not Call Registry
       since #{facts.dnc_date}.

    6. Between #{facts.first_date} and #{facts.last_date}, Defendant placed #{facts.total_count}
       unauthorized telemarketing #{facts.channel_label} to Plaintiff's wireless number.

    7. Plaintiff did not provide prior express consent for these contacts.

    8. Plaintiff sent Defendant a written demand for settlement.#{stop_detail} Plaintiff
       notified Defendant that failure to settle would result in a claim for
       #{format_money(FilingLimits.per_violation_damages())} per violation at trial.

    9. Each contact was willful or knowing under 47 U.S.C. § 227(b)(3).

    FIRST CAUSE OF ACTION
    (Violation of 47 U.S.C. § 227(b) — Unauthorized Calls/Texts to Wireless Number)

    10. Plaintiff incorporates paragraphs 1–9.

    11. Defendant violated 47 U.S.C. § 227(b)(1)(A)(iii) by placing automated or prerecorded
        telemarketing #{facts.channel_label} to Plaintiff's wireless number without consent.

    SECOND CAUSE OF ACTION
    (Violation of 47 U.S.C. § 227(c) — National Do Not Call Registry)

    12. Plaintiff incorporates paragraphs 1–9.

    13. Defendant violated the National Do Not Call Registry rules by telemarketing Plaintiff's
        registered number in violation of 47 U.S.C. § 227(c) and 47 C.F.R. § 64.1200.

    DAMAGES

    14. Plaintiff seeks statutory damages of #{format_money(FilingLimits.per_violation_damages())}
        per violation for #{facts.total_count} violations, totaling #{format_money(facts.total_damages)},
        plus costs of suit and such other relief as the Court deems just.

    PRAYER FOR RELIEF

    WHEREFORE, Plaintiff prays for judgment against Defendant as follows:

    a. Damages in the amount of #{format_money(facts.total_damages)};
    b. Costs of suit; and
    c. Such other relief as the Court deems just and proper.

    Dated: #{facts.letter_date}

    _________________________________
    #{facts.claimant_name}, Plaintiff In Pro Per
    """
    |> String.trim()
  end

  defp declaration(facts) do
    """
    ================================================================================
    5. DECLARATION IN SUPPORT OF COMPLAINT
    ================================================================================

    I, #{facts.claimant_name}, declare under penalty of perjury under the laws of the State
    of California that I have read the Complaint and know the contents are true of my own
    knowledge except as to matters stated on information and belief, and as to those matters
    I believe them to be true.

    Executed on #{facts.letter_date} at #{facts.county}, California.


    _________________________________
    #{facts.claimant_name}
    """
    |> String.trim()
  end

  defp damages_worksheet(facts) do
    """
    ================================================================================
    6. DAMAGES WORKSHEET
    ================================================================================

    Trial rate (#{format_money(FilingLimits.per_violation_damages())} per willful violation):
      Count: #{facts.total_count}
      Total: #{format_money(facts.total_damages)}

    Small claims cap (for reference): #{format_money(FilingLimits.small_claims_max())}
    Amount filed in this civil action: #{format_money(facts.total_damages)}
    """
    |> String.trim()
  end

  defp exhibit_index(facts, attachments) do
    demand_exhibit =
      if facts.case.letter_draft not in [nil, ""] do
        ["- Exhibit A: Demand letter"]
      else
        []
      end

    tracking_exhibit =
      if facts.case.mail_tracking_number not in [nil, ""] do
        ["- Exhibit B: USPS certified mail proof (#{facts.case.mail_tracking_number})"]
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

    body =
      (demand_exhibit ++ tracking_exhibit ++ attachment_lines)
      |> case do
        [] -> "(No exhibits listed yet.)"
        lines -> Enum.join(lines, "\n")
      end

    """
    ================================================================================
    7. EXHIBIT INDEX
    ================================================================================

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
        "(No violations marked.)"
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
    8. VIOLATION SCHEDULE
    ================================================================================

    #{table}
    """
    |> String.trim()
  end

  defp service_notes(facts) do
    """
    ================================================================================
    9. SERVICE OF PROCESS
    ================================================================================

    Serve Defendant #{facts.defendant_name} at #{single_line_address(facts.defendant_address)}.
    You cannot serve papers yourself. Use a process server or someone 18+ who is not a party.
    File Proof of Service (POS-010) after service.
    """
    |> String.trim()
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

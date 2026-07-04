defmodule DncWatchdog.Enforcement.LetterDraft do
  @moduledoc """
  Builds certified-mail TCPA demand letter drafts from case evidence.
  """

  alias DncWatchdog.Enforcement.Case
  alias DncWatchdog.Enforcement.ClaimantProfile
  alias DncWatchdog.Enforcement.EvidenceAttachment
  alias DncWatchdog.Enforcement.LegalEntity

  @standard_damages Decimal.new("500.00")
  @willful_damages Decimal.new("1500.00")

  @doc """
  Renders a TCPA demand letter draft for certified mail with a settlement demand.
  """
  def render(%Case{} = case, violations, attachments, opts \\ []) do
    profile = Keyword.get(opts, :claimant_profile)

    claimant_name = ClaimantProfile.resolve(:name, Keyword.get(opts, :claimant_name), case.claimant_name, profile)
    claimant_address = ClaimantProfile.resolve(:address, Keyword.get(opts, :claimant_address), case.claimant_address, profile)
    claimant_phone = ClaimantProfile.resolve(:phone, Keyword.get(opts, :claimant_phone), case.claimant_phone, profile)
    claimant_email = ClaimantProfile.resolve(:email, Keyword.get(opts, :claimant_email), case.claimant_email, profile)
    dnc_date = dnc_date(case, opts, profile)
    stop_date = stop_contact_date(case, opts)
    county = ClaimantProfile.resolve(:small_claims_county, Keyword.get(opts, :small_claims_county), case.small_claims_county, profile)
    entity = case.legal_entity
    company_name = defendant_name(entity, case)

    sorted_violations = Enum.sort_by(violations, & &1.timestamp, NaiveDateTime)
    {standard_violations, willful_violations} = split_violations(sorted_violations, stop_date)

    standard_count = length(standard_violations)
    willful_count = length(willful_violations)
    total_count = standard_count + willful_count

    standard_total = Decimal.mult(@standard_damages, Decimal.new(standard_count))
    willful_total = Decimal.mult(@willful_damages, Decimal.new(willful_count))
    total_statutory = Decimal.add(standard_total, willful_total)
    settlement_amount = settlement_amount(case, total_statutory, opts)

    {first_date, last_date} = violation_date_range(sorted_violations)
    channel_label = channel_label(sorted_violations)
    evidence_types = evidence_types(sorted_violations, attachments)
    willful_paragraph = willful_paragraph(stop_date, willful_count)
    damages_breakdown = damages_breakdown(standard_count, standard_total, willful_count, willful_total, total_statutory)
    tcpa_quotes = tcpa_statutory_quotes_section(sorted_violations)
    appendix = violation_appendix(sorted_violations, attachments)

    recipient_block = recipient_block(entity, company_name)
    letter_date = format_letter_date(Date.utc_today())

    """
    #{claimant_name}
    #{claimant_address}
    #{claimant_phone}
    #{claimant_email}

    #{letter_date}

    #{recipient_block}

    VIA CERTIFIED MAIL – RETURN RECEIPT REQUESTED

    RE: DEMAND FOR SETTLEMENT – VIOLATIONS OF THE TELEPHONE CONSUMER PROTECTION ACT (47 U.S.C. § 227)

    Dear Legal Department / Management,

    This letter serves as formal notice that #{company_name} has systematically violated the Telephone Consumer Protection Act (TCPA), 47 U.S.C. § 227, as well as the rules of the Federal Communications Commission (FCC) and Federal Trade Commission (FTC), by placing unauthorized #{channel_label} to my personal wireless phone number, #{claimant_phone}.

    I have never registered to receive marketing or other communications from you, nor have I provided prior express consent for your company to contact me at this number.

    My phone number has been continuously registered on the National Do Not Call Registry since #{dnc_date}. Under 47 U.S.C. § 227(c) and 47 C.F.R. § 64.1200, it is a violation of federal law to make telemarketing calls or texts to a number listed on the National Do Not Call Registry.
    #{tcpa_quotes}#{willful_paragraph}
    Summary of Violations:

    Between #{first_date} and #{last_date}, your company placed a total of #{total_count} unauthorized #{channel_label} to my phone. I have fully documented these infractions, including dates, timestamps, originating numbers, call routing details, and #{evidence_types}.

    Under the TCPA, a private right of action allows for statutory damages of $500 per violation, which scales up to $1,500 per violation if the conduct is found to be willful or knowing.

    #{damages_breakdown}
    Demand for Settlement:

    I prefer to resolve this matter efficiently out of court. I am willing to settle all outstanding claims regarding these violations in exchange for a single payment of #{format_money(settlement_amount)}, payable to me within 14 calendar days of your receipt of this letter.

    If we are unable to reach an amicable settlement within this timeframe, I intend to file a formal complaint in #{county} Small Claims Court or with the appropriate federal agencies without further notice. Please note that I will seek the maximum statutory damages of $1,500 per violation at trial, alongside any applicable court costs.

    Please contact me in writing at #{claimant_email} or by mail at the address listed above to confirm your receipt of this demand and to arrange for payment.

    Sincerely,

    #{claimant_name}
    #{appendix}
    """
    |> String.trim()
  end

  defp recipient_block(%LegalEntity{} = entity, company_name) do
    attn =
      case entity.attn do
        attn when attn not in [nil, ""] -> "#{company_name} / #{attn}"
        _ -> company_name
      end

    city_state_zip =
      [entity.city, entity.state, entity.zip]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(", ")

    lines =
      [attn, entity.street, city_state_zip]
      |> Enum.reject(&(&1 in [nil, ""]))

    Enum.join(lines, "\n")
  end

  defp recipient_block(_, company_name) do
    """
    #{company_name}
    [Company Address]
    [Company City, State, Zip]
    """
    |> String.trim()
  end

  defp defendant_name(%LegalEntity{legal_name: name}, _case) when name not in [nil, ""], do: name

  defp defendant_name(_, %Case{company_name: name}) when name not in [nil, ""], do: name

  defp defendant_name(_, _), do: "[Company Name]"

  defp dnc_date(%Case{dnc_registration_date: %Date{} = date}, _opts, _profile), do: format_letter_date(date)

  defp dnc_date(%Case{} = case, opts, profile) do
    case ClaimantProfile.resolve(:dnc_registration_date, Keyword.get(opts, :dnc_registration_date), case.dnc_registration_date, profile) do
      %Date{} = date -> format_letter_date(date)
      value -> value
    end
  end

  defp stop_contact_date(%Case{stop_contact_date: %Date{} = date}, _opts), do: date

  defp stop_contact_date(%Case{}, opts) do
    Keyword.get(opts, :stop_contact_date)
  end

  defp settlement_amount(%Case{settlement_amount: %Decimal{} = amount}, _total, _opts), do: amount

  defp settlement_amount(%Case{}, total, opts) do
    Keyword.get(opts, :settlement_amount) || total
  end

  defp split_violations(violations, %Date{} = stop_date) do
    Enum.split_with(violations, fn comm ->
      Date.compare(NaiveDateTime.to_date(comm.timestamp), stop_date) != :gt
    end)
  end

  defp split_violations(violations, _), do: {violations, []}

  defp willful_paragraph(%Date{} = stop_date, willful_count) when willful_count > 0 do
    """

    Furthermore, I explicitly revoked any implied consent and demanded that your company stop contacting me on #{format_letter_date(stop_date)}. Despite this clear revocation, your company continued to contact me, elevating these infractions to "willful and knowing" violations under 47 U.S.C. § 227(b)(3).
    """
  end

  defp willful_paragraph(_, _), do: ""

  defp tcpa_statutory_quotes_section(violations) do
    quotes =
      []
      |> maybe_add_quote(wireless_contact?(violations), wireless_autodialer_quote())
      |> maybe_add_quote(true, dnc_registry_quote())
      |> maybe_add_quote(true, private_right_of_action_quote())

    case quotes do
      [] ->
        ""

      items ->
        """

        Applicable Violations of Federal Law:

        Your conduct violates the following provisions of the Telephone Consumer Protection Act, 47 U.S.C. § 227:

        #{Enum.join(items, "\n\n")}
        """
    end
  end

  defp maybe_add_quote(quotes, true, quote), do: quotes ++ [quote]
  defp maybe_add_quote(quotes, false, _quote), do: quotes

  defp wireless_contact?(violations) do
    Enum.any?(violations, fn comm ->
      call_channel?(comm.channel) or text_channel?(comm.channel)
    end)
  end

  defp wireless_autodialer_quote do
    """
    Section 227(b)(1)(A)(iii) provides in relevant part:

    "It shall be unlawful for any person within the United States ... to make any call (other than a call made for emergency purposes or made with the prior express consent of the called party) using any automatic telephone dialing system or an artificial or prerecorded voice ... to any telephone number assigned to ... a cellular telephone service ..."
    """
    |> String.trim()
  end

  defp dnc_registry_quote do
    """
    Section 227(c)(5) provides:

    "It shall be unlawful for any person to initiate any telephone solicitation to ... a residential subscriber who has registered the subscriber's telephone number on the national do-not-call registry."
    """
    |> String.trim()
  end

  defp private_right_of_action_quote do
    """
    Section 227(b)(3) establishes my private right of action and remedies:

    "A person or entity may ... bring ... an action to recover for actual monetary loss from such a violation, or to receive $500 in damages for each such violation, except that the court may ... increase the amount of the award ... to an amount not to exceed $1,500" if the violation was willful or knowing.
    """
    |> String.trim()
  end

  defp damages_breakdown(standard_count, standard_total, willful_count, willful_total, total_statutory) do
    lines =
      [
        "#{standard_count} Standard Violations × $500 = #{format_money(standard_total)}",
        if(willful_count > 0,
          do: "#{willful_count} Willful Violations × $1,500 = #{format_money(willful_total)}",
          else: nil
        ),
        "TOTAL STATUTORY DAMAGES: #{format_money(total_statutory)}"
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(lines, "\n")
  end

  defp violation_date_range([]), do: {"[Date of first violation]", "[Date of last violation]"}

  defp violation_date_range(violations) do
    first = violations |> List.first() |> Map.fetch!(:timestamp) |> format_letter_date()
    last = violations |> List.last() |> Map.fetch!(:timestamp) |> format_letter_date()
    {first, last}
  end

  defp channel_label(violations) do
    channels =
      violations
      |> Enum.map(& &1.channel)
      |> Enum.uniq()

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

  defp evidence_types(violations, attachments) do
    types =
      []
      |> maybe_add_type(attachments != [], "screenshots")
      |> maybe_add_type(Enum.any?(violations, &text_channel?(&1.channel)), "text transcripts")
      |> maybe_add_type(Enum.any?(violations, &call_channel?(&1.channel)), "voicemail recordings")

    case types do
      [] -> "screenshots, text transcripts, and voicemail recordings"
      [one] -> one
      [first, second] -> "#{first} and #{second}"
      types -> Enum.join(Enum.slice(types, 0..-2//1), ", ") <> ", and " <> List.last(types)
    end
  end

  defp maybe_add_type(types, true, label), do: types ++ [label]
  defp maybe_add_type(types, false, _label), do: types

  defp violation_appendix(violations, attachments) do
    events_table =
      violations
      |> Enum.map(fn comm ->
        time = format_timestamp(comm.timestamp)
        body = String.slice(comm.body || "", 0, 80)
        "| #{time} | #{comm.channel} | #{comm.from_number} | #{body} |"
      end)
      |> Enum.join("\n")

    exhibits =
      attachments
      |> Enum.with_index(1)
      |> Enum.map(fn {%EvidenceAttachment{} = att, idx} ->
        label = att.caption || att.filename
        "- Exhibit #{exhibit_letter(idx)}: #{label}"
      end)
      |> Enum.join("\n")

    sections = []

    sections =
      if events_table != "" do
        sections ++
          [
            """

            Appendix: Documented Contacts

            | Date & Time | Channel | From | Message (excerpt) |
            | --- | --- | --- | --- |
            #{events_table}
            """
          ]
      else
        sections
      end

    sections =
      if exhibits != "" do
        sections ++
          [
            """

            Attached Exhibits

            #{exhibits}
            """
          ]
      else
        sections
      end

    sections |> Enum.join("") |> String.trim()
    |> case do
      "" -> ""
      appendix -> "\n\n" <> appendix
    end
  end

  defp format_money(%Decimal{} = amount) do
    amount
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
    |> then(&"$#{&1}")
  end

  defp format_letter_date(%Date{} = date) do
    Calendar.strftime(date, "%B %-d, %Y")
  end

  defp format_letter_date(%NaiveDateTime{} = dt) do
    dt |> NaiveDateTime.to_date() |> format_letter_date()
  end

  defp format_letter_date(value) when is_binary(value), do: value

  defp format_timestamp(%NaiveDateTime{} = dt) do
    dt
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_string()
  end

  defp format_timestamp(value), do: to_string(value)

  defp exhibit_letter(idx) when idx <= 26, do: <<?A + idx - 1>>
  defp exhibit_letter(idx), do: "Ex#{idx}"
end

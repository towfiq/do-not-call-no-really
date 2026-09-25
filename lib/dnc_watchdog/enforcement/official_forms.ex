defmodule DncWatchdog.Enforcement.OfficialForms do
  @moduledoc """
  Picks the official Judicial Council of California forms a case needs and maps
  case data onto their PDF fields. Everything here is California-specific: the
  form codes, the venue rules, and the Santa Clara court caption.

  Small claims files SC-100 on its own. Civil (limited or unlimited) files the
  generated complaint as the lead document with SUM-100 and CM-010 attached.
  POS-010 is prepared for service after the clerk returns a case number, so it is
  not part of the filing packet.
  """

  alias DncWatchdog.Enforcement.Case
  alias DncWatchdog.Enforcement.ClaimantProfile
  alias DncWatchdog.Enforcement.EfilePayload
  alias DncWatchdog.Enforcement.FilingLimits
  alias DncWatchdog.Enforcement.LegalEntity
  alias DncWatchdog.Enforcement.PdfForms
  alias DncWatchdog.Enforcement.Phone

  @court_county "Santa Clara"
  @court_street "191 North First Street"
  @court_city_zip "San Jose, CA 95113"
  @court_branch "Downtown Superior Court"
  @default_county "Santa Clara County"

  @forms %{
    "SC-100" => %{
      code: "SC-100",
      title: "Plaintiff's Claim and ORDER to Go to Small Claims Court",
      filing_code_hints: ["Plaintiff's Claim", "SC-100", "Complaint"],
      lead?: true,
      venues: ["small_claims"]
    },
    "SUM-100" => %{
      code: "SUM-100",
      title: "Summons",
      filing_code_hints: ["Summons"],
      lead?: false,
      venues: ["limited_civil", "unlimited_civil"]
    },
    "CM-010" => %{
      code: "CM-010",
      title: "Civil Case Cover Sheet",
      filing_code_hints: ["Civil Case Cover Sheet", "Case Cover Sheet"],
      lead?: false,
      venues: ["limited_civil", "unlimited_civil"]
    },
    "POS-010" => %{
      code: "POS-010",
      title: "Proof of Service of Summons",
      filing_code_hints: ["Proof of Service: Mail", "Proof of Service"],
      lead?: false,
      venues: []
    }
  }

  @doc """
  Forms to file with the initial filing for `venue`, in packet order.
  """
  def for_venue(venue) do
    ["SC-100", "SUM-100", "CM-010"]
    |> Enum.map(&Map.fetch!(@forms, &1))
    |> Enum.filter(&(venue in &1.venues))
    |> Enum.map(&Map.put(&1, :filename, filename(&1.code)))
  end

  def spec(code), do: Map.get(@forms, String.upcase(code))

  @doc """
  Download filename for a form, e.g. `"sc100.pdf"`.
  """
  def filename(code) do
    code |> String.downcase() |> String.replace("-", "") |> Kernel.<>(".pdf")
  end

  @doc """
  Form code for a download filename, e.g. `"sc100.pdf"` -> `"SC-100"`.
  """
  def code_from_filename(name) do
    slug = name |> Path.basename(".pdf") |> String.downcase() |> String.replace("-", "")
    Enum.find(codes(), &(filename(&1) == slug <> ".pdf"))
  end

  def codes, do: Map.keys(@forms)

  @doc """
  Fills one form and returns the PDF binary.
  """
  def fill(code, %Case{} = case_record, violations, opts \\ []) do
    spec = spec(code)

    cond do
      is_nil(spec) ->
        {:error, {:unknown_form, code}}

      true ->
        PdfForms.render([{:form, spec.code, fields(spec.code, case_record, violations, opts)}])
    end
  end

  @doc """
  PDF field values for one form, keyed by fully qualified AcroForm field name.
  """
  def fields(code, %Case{} = case_record, violations, opts \\ []) do
    data = build_data(case_record, violations, opts)

    case String.upcase(code) do
      "SC-100" -> sc100_fields(data)
      "SUM-100" -> sum100_fields(data)
      "CM-010" -> cm010_fields(data)
      "POS-010" -> pos010_fields(data)
    end
  end

  defp build_data(%Case{} = case_record, violations, opts) do
    profile = Keyword.get(opts, :claimant_profile)
    limits = Keyword.get(opts, :filing_limits) || FilingLimits.assess(length(violations))

    name = resolve(:name, case_record.claimant_name, profile)
    address_text = resolve(:address, case_record.claimant_address, profile)
    phone = resolve(:phone, case_record.claimant_phone, profile)
    email = resolve(:email, case_record.claimant_email, profile)
    county = resolve(:small_claims_county, case_record.small_claims_county, profile)
    county = if county in [nil, "", "[Your County]"], do: @default_county, else: county

    entity = case_record.legal_entity
    sorted = Enum.sort_by(violations, & &1.timestamp, NaiveDateTime)

    %{
      case: case_record,
      claimant_name: name,
      claimant_address: EfilePayload.parse_address(address_text),
      claimant_phone: format_phone(phone),
      claimant_email: email,
      county: county,
      defendant_name: defendant_name(entity, case_record),
      defendant_phone: format_phone(entity_phone(entity)),
      defendant_address: entity_address(entity),
      agent: LegalEntity.service_agent(entity),
      limits: limits,
      venue: limits.recommended_venue,
      claim_amount: claim_amount(limits),
      violation_count: limits.violation_count,
      channel_label: channel_label(sorted),
      dnc_date: dnc_date(case_record, profile),
      first_date: first_date(sorted),
      last_date: last_date(sorted),
      today: format_date(Date.utc_today())
    }
  end

  defp sc100_fields(data) do
    %{
      "SC-100[0].Page1[0].CaptionRight[0].County[0].CourtInfo[0]" =>
        "#{@court_county}\n#{@court_street}\n#{@court_city_zip}",
      "SC-100[0].Page2[0].PxCaption[0].Plaintiff[0]" => data.claimant_name,
      "SC-100[0].Page2[0].List1[0].Item1[0].PlaintiffName1[0]" => data.claimant_name,
      "SC-100[0].Page2[0].List1[0].Item1[0].PlaintiffPhone1[0]" => data.claimant_phone,
      "SC-100[0].Page2[0].List1[0].Item1[0].PlaintiffAddress1[0]" => data.claimant_address.street,
      "SC-100[0].Page2[0].List1[0].Item1[0].PlaintiffCity1[0]" => data.claimant_address.city,
      "SC-100[0].Page2[0].List1[0].Item1[0].PlaintiffState1[0]" => data.claimant_address.state,
      "SC-100[0].Page2[0].List1[0].Item1[0].PlaintiffZip1[0]" => data.claimant_address.zip,
      "SC-100[0].Page2[0].List1[0].Item1[0].EmailAdd1[0]" => data.claimant_email,
      "SC-100[0].Page2[0].List2[0].item2[0].DefendantName1[0]" => data.defendant_name,
      "SC-100[0].Page2[0].List2[0].item2[0].DefendantPhone1[0]" => data.defendant_phone,
      "SC-100[0].Page2[0].List2[0].item2[0].DefendantAddress1[0]" =>
        data.defendant_address.street,
      "SC-100[0].Page2[0].List2[0].item2[0].DefendantCity1[0]" => data.defendant_address.city,
      "SC-100[0].Page2[0].List2[0].item2[0].DefendantState1[0]" => data.defendant_address.state,
      "SC-100[0].Page2[0].List2[0].item2[0].DefendantZip1[0]" => data.defendant_address.zip,
      "SC-100[0].Page2[0].List2[0].item2[0].DefendantName2[0]" => agent_field(data.agent, :name),
      "SC-100[0].Page2[0].List2[0].item2[0].DefendantJob1[0]" => agent_field(data.agent, :title),
      "SC-100[0].Page2[0].List2[0].item2[0].DefendantAddress2[0]" =>
        agent_field(data.agent, :street),
      "SC-100[0].Page2[0].List2[0].item2[0].DefendantCity2[0]" => agent_field(data.agent, :city),
      "SC-100[0].Page2[0].List2[0].item2[0].DefendantState2[0]" =>
        agent_field(data.agent, :state),
      "SC-100[0].Page2[0].List2[0].item2[0].DefendantZip2[0]" => agent_field(data.agent, :zip),
      "SC-100[0].Page2[0].List3[0].PlaintiffClaimAmount1[0]" => money(data.claim_amount),
      "SC-100[0].Page2[0].List3[0].Lia[0].FillField2[0]" => claim_reason(data),
      "SC-100[0].Page3[0].PxCaption[0].Plaintiff[0]" => data.claimant_name,
      "SC-100[0].Page3[0].List3[0].Lib[0].Date2[0]" => data.first_date,
      "SC-100[0].Page3[0].List3[0].Lib[0].Date3[0]" => data.last_date,
      "SC-100[0].Page3[0].List3[0].Lic[0].FillField1[0]" => damages_explanation(data),
      # Item 4: plaintiff asked the defendant to stop/pay via the demand letter.
      "SC-100[0].Page3[0].List4[0].Item4[0].Checkbox50[0]" => true,
      # Item 5a: venue is where the plaintiff was injured by the calls and texts.
      "SC-100[0].Page3[0].List5[0].Lia[0].Checkbox5cb[0]" => true,
      "SC-100[0].Page3[0].List6[0].item6[0].ZipCode1[0]" => data.claimant_address.zip,
      # Item 7: not an attorney-client fee dispute. Item 8: not a public entity.
      "SC-100[0].Page3[0].List7[0].item7[0].Checkbox60[1]" => true,
      "SC-100[0].Page3[0].List8[0].item8[0].Checkbox61[1]" => true,
      "SC-100[0].Page4[0].PxCaption[0].Plaintiff[0]" => data.claimant_name,
      "SC-100[0].Page4[0].List9[0].Item9[0].Checkbox62[1]" => true,
      "SC-100[0].Page4[0].List10[0].li10[0].Checkbox63[0]" => over_2500?(data.claim_amount),
      "SC-100[0].Page4[0].List10[0].li10[0].Checkbox63[1]" => !over_2500?(data.claim_amount),
      "SC-100[0].Page4[0].Sign[0].Date1[0]" => data.today,
      "SC-100[0].Page4[0].Sign[0].PlaintiffName1[0]" => data.claimant_name
    }
    |> drop_blanks()
  end

  defp sum100_fields(data) do
    %{
      "SUM-100[0].Page1[0].Notice[0].FillText25[0]" => data.defendant_name,
      "SUM-100[0].Page1[0].Notice[0].FillText180[0]" => data.claimant_name,
      # The first court field is narrow, so the name wraps onto the address line.
      "SUM-100[0].Page1[0].Info[0].FillText3[0]" => "Superior Court of California,",
      "SUM-100[0].Page1[0].Info[0].FillText2[0]" =>
        "County of #{@court_county}, #{@court_street}, #{@court_city_zip}",
      "SUM-100[0].Page1[0].Info[0].FillText30[0]" => plaintiff_contact_block(data),
      # Served on behalf of the defendant entity under CCP 416.10 (corporation).
      "SUM-100[0].Page1[0].Noticeto[0].List[0].Li3[0].ServiceDef_cb[0]" => business?(data),
      "SUM-100[0].Page1[0].Noticeto[0].List[0].Li3[0].FillText15[0]" =>
        if(business?(data), do: data.defendant_name),
      "SUM-100[0].Page1[0].Noticeto[0].List[0].Li3[0].SubLi3[0].ServiceSection_cb[0]" =>
        business?(data),
      "SUM-100[0].Page1[0].Noticeto[0].List[0].Li1[0].ServiceDef_cb[0]" => !business?(data)
    }
    |> drop_blanks()
  end

  defp cm010_fields(data) do
    %{
      "CM-010[0].Page1[0].P1Caption[0].AttyPartyInfo[0].Name[0]" =>
        "#{data.claimant_name} (Self-Represented)",
      "CM-010[0].Page1[0].P1Caption[0].AttyPartyInfo[0].Street[0]" =>
        data.claimant_address.street,
      "CM-010[0].Page1[0].P1Caption[0].AttyPartyInfo[0].City[0]" => data.claimant_address.city,
      "CM-010[0].Page1[0].P1Caption[0].AttyPartyInfo[0].State[0]" => data.claimant_address.state,
      "CM-010[0].Page1[0].P1Caption[0].AttyPartyInfo[0].Zip[0]" => data.claimant_address.zip,
      "CM-010[0].Page1[0].P1Caption[0].AttyPartyInfo[0].Phone[0]" => data.claimant_phone,
      "CM-010[0].Page1[0].P1Caption[0].AttyPartyInfo[0].Email[0]" => data.claimant_email,
      "CM-010[0].Page1[0].P1Caption[0].AttyPartyInfo[0].AttyFor[0]" => "Plaintiff in Pro Per",
      "CM-010[0].Page1[0].P1Caption[0].CourtInfo[0].CrtCounty[0]" => @court_county,
      "CM-010[0].Page1[0].P1Caption[0].CourtInfo[0].CrtStreet[0]" => @court_street,
      "CM-010[0].Page1[0].P1Caption[0].CourtInfo[0].CrtCityZip[0]" => @court_city_zip,
      "CM-010[0].Page1[0].P1Caption[0].CourtInfo[0].CrtBranch[0]" => @court_branch,
      "CM-010[0].Page1[0].P1Caption[0].TitlePartyName[0].Party1[0]" => case_name(data),
      "CM-010[0].Page1[0].P1Caption[0].FormTitle[0].Civil[0].limited1[0]" =>
        data.venue == "unlimited_civil",
      "CM-010[0].Page1[0].P1Caption[0].FormTitle[0].Civil[0].limited1[1]" =>
        data.venue != "unlimited_civil",
      # Item 1: "Other complaint (not specified above) (42)".
      "CM-010[0].Page1[0].List1[0].Item1Check[41]" => true,
      # Item 2: not complex. Item 3a: monetary relief. Item 5: not a class action.
      "CM-010[0].Page2[0].List2[0].is1[1]" => true,
      "CM-010[0].Page2[0].List3[0].Item3[0].Lia[0].Ch1[0]" => true,
      "CM-010[0].Page2[0].List4[0].FillText1[0]" =>
        "2 (47 U.S.C. § 227(b); 47 U.S.C. § 227(c) and 47 C.F.R. § 64.1200)",
      "CM-010[0].Page2[0].List5[0].is[1]" => true,
      "CM-010[0].Page2[0].SigDate[0]" => data.today,
      "CM-010[0].Page2[0].SigName[0]" => data.claimant_name
    }
    |> drop_blanks()
  end

  defp pos010_fields(data) do
    %{
      "POS-010[0].Page1[0].P1Caption[0].AttyPartyInfo[0].TextField1[0]" =>
        plaintiff_contact_block(data),
      "POS-010[0].Page1[0].P1Caption[0].AttyPartyInfo[0].Phone[0]" => data.claimant_phone,
      "POS-010[0].Page1[0].P1Caption[0].AttyPartyInfo[0].Email[0]" => data.claimant_email,
      "POS-010[0].Page1[0].P1Caption[0].AttyPartyInfo[0].Nmae[0]" => "Plaintiff in Pro Per",
      "POS-010[0].Page1[0].P1Caption[0].CourtInfo[0].CrtCounty[0]" => @court_county,
      "POS-010[0].Page1[0].P1Caption[0].CourtInfo[0].CrtStreet[0]" => @court_street,
      "POS-010[0].Page1[0].P1Caption[0].CourtInfo[0].CrtCityZip[0]" => @court_city_zip,
      "POS-010[0].Page1[0].P1Caption[0].CourtInfo[0].CrtBranch[0]" => @court_branch,
      "POS-010[0].Page1[0].P1Caption[0].TitlePartyName[0].Party1[0]" => data.claimant_name,
      "POS-010[0].Page1[0].P1Caption[0].TitlePartyName[0].Party2[0]" => data.defendant_name,
      "POS-010[0].Page1[0].List3[0].Lia[0].FillText1[0]" => data.defendant_name
    }
    |> drop_blanks()
  end

  defp claim_reason(data) do
    "Defendant placed #{data.violation_count} unwanted telemarketing #{data.channel_label} " <>
      "to plaintiff's wireless number #{data.claimant_phone} between #{data.first_date} and " <>
      "#{data.last_date}, while the number was registered on the National Do Not Call Registry " <>
      "(registered #{data.dnc_date}). Plaintiff never gave prior express written consent. " <>
      "This violates the Telephone Consumer Protection Act, 47 U.S.C. § 227, and 47 C.F.R. § 64.1200. " <>
      "See the attached statement of facts, declaration, and exhibits."
  end

  defp damages_explanation(data) do
    per = money(FilingLimits.per_violation_damages())
    total = money(data.limits.total_damages)

    base =
      "#{data.violation_count} violations × #{per} in treble damages for willful or knowing " <>
        "violations under 47 U.S.C. § 227(b)(3) and (c)(5) = #{total}."

    if data.limits.exceeds_small_claims_amount_cap do
      base <> " Claim filed at the #{money(FilingLimits.small_claims_max())} small claims limit."
    else
      base
    end
  end

  defp plaintiff_contact_block(data) do
    [
      data.claimant_name,
      data.claimant_address.street,
      locality(data.claimant_address),
      data.claimant_phone
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
  end

  defp case_name(data) do
    "#{data.claimant_name} v. #{data.defendant_name}"
  end

  defp locality(%{city: city, state: state, zip: zip}) do
    [city, state, zip] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(", ")
  end

  defp business?(%{case: %Case{legal_entity: %LegalEntity{entity_type: "individual"}}}), do: false
  defp business?(_), do: true

  defp agent_field(nil, _key), do: nil
  defp agent_field(agent, key), do: Map.get(agent, key)

  defp entity_phone(%LegalEntity{phone: phone}) when phone not in [nil, ""], do: phone
  defp entity_phone(_), do: nil

  defp entity_address(%LegalEntity{} = entity) do
    %{street: entity.street, city: entity.city, state: entity.state, zip: entity.zip}
  end

  defp entity_address(_), do: %{street: nil, city: nil, state: nil, zip: nil}

  defp defendant_name(%LegalEntity{legal_name: name}, _case) when name not in [nil, ""], do: name
  defp defendant_name(_, %Case{company_name: name}) when name not in [nil, ""], do: name
  defp defendant_name(_, _), do: nil

  defp claim_amount(%{recommended_venue: "small_claims"} = limits),
    do: limits.small_claims_claim_amount

  defp claim_amount(limits), do: limits.total_damages

  defp over_2500?(%Decimal{} = amount) do
    Decimal.compare(amount, FilingLimits.small_claims_high_threshold()) == :gt
  end

  defp resolve(key, case_value, profile) do
    ClaimantProfile.resolve(key, nil, case_value, profile)
  end

  defp dnc_date(%Case{} = case_record, profile) do
    case resolve(:dnc_registration_date, case_record.dnc_registration_date, profile) do
      %Date{} = date -> format_date(date)
      value -> value
    end
  end

  defp first_date([]), do: nil
  defp first_date([first | _]), do: format_date(first.timestamp)

  defp last_date([]), do: nil

  defp last_date(violations),
    do: violations |> List.last() |> Map.fetch!(:timestamp) |> format_date()

  defp channel_label(violations) do
    channels = Enum.map(violations, & &1.channel)
    calls? = Enum.any?(channels, &(&1 in ["call", "phone", "voice", "voicemail"]))
    texts? = Enum.any?(channels, &(&1 in ["sms", "text", "imessage", "message"]))

    case {calls?, texts?} do
      {true, true} -> "calls and text messages"
      {true, false} -> "calls"
      {false, true} -> "text messages"
      _ -> "calls and text messages"
    end
  end

  defp format_phone(nil), do: nil
  defp format_phone(phone), do: Phone.format(phone) || phone

  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%m/%d/%Y")
  defp format_date(%NaiveDateTime{} = dt), do: dt |> NaiveDateTime.to_date() |> format_date()
  defp format_date(value) when is_binary(value), do: value
  defp format_date(_), do: nil

  defp money(%Decimal{} = amount) do
    amount |> Decimal.round(2) |> Decimal.to_string(:normal)
  end

  defp money(_), do: nil

  # Placeholders like "[Your Name]" belong in a draft, never on a filed court form.
  defp drop_blanks(fields) do
    fields
    |> Enum.reject(fn {_key, value} -> value in [nil, "", false] or placeholder?(value) end)
    |> Map.new()
  end

  defp placeholder?(value) when is_binary(value), do: Regex.match?(~r/\[[^\]]+\]/, value)
  defp placeholder?(_), do: false
end

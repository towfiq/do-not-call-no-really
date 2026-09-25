defmodule DncWatchdog.Enforcement.OfficialFormsTest do
  use DncWatchdog.DataCase, async: true

  import DncWatchdog.EnforcementFixtures

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.OfficialForms
  alias DncWatchdog.Enforcement.PdfForms

  describe "for_venue/1" do
    test "small claims files SC-100 as the lead document" do
      assert [%{code: "SC-100", lead?: true, filename: "sc100.pdf"}] =
               OfficialForms.for_venue("small_claims")
    end

    test "civil files the summons and cover sheet behind the complaint" do
      codes = Enum.map(OfficialForms.for_venue("limited_civil"), & &1.code)
      assert codes == ["SUM-100", "CM-010"]
      refute Enum.any?(OfficialForms.for_venue("limited_civil"), & &1.lead?)

      assert OfficialForms.for_venue("unlimited_civil") ==
               OfficialForms.for_venue("limited_civil")
    end
  end

  describe "fields/4" do
    setup do
      case_record =
        case_fixture(%{
          claimant_name: "Jane Doe",
          claimant_address: "855 Newell Place\nPalo Alto, CA 94303",
          claimant_phone: "4159719595",
          claimant_email: "jane@example.com",
          dnc_registration_date: ~D[2008-01-04]
        })

      {:ok, case_record} =
        Enforcement.upsert_case_legal_entity(case_record, %{
          legal_name: "Acme Robocallers LLC",
          street: "1 Market St",
          city: "San Jose",
          state: "CA",
          zip: "95113",
          phone: "4085550000",
          agent_name: "Pat Agent",
          agent_title: "Registered Agent",
          agent_street: "2 Mission St",
          agent_city: "San Francisco",
          agent_state: "CA",
          agent_zip: "94105"
        })

      violation =
        communication_fixture(%{
          case_id: case_record.id,
          violation_status: "violation",
          channel: "sms",
          timestamp: ~N[2026-06-04 10:00:00]
        })

      %{case: Enforcement.get_case!(case_record.id), violations: [violation]}
    end

    test "SC-100 carries the parties, agent for service, and claim amount", %{
      case: case_record,
      violations: violations
    } do
      fields = OfficialForms.fields("SC-100", case_record, violations)

      assert fields["SC-100[0].Page2[0].List1[0].Item1[0].PlaintiffName1[0]"] == "Jane Doe"
      assert fields["SC-100[0].Page2[0].List1[0].Item1[0].PlaintiffCity1[0]"] == "Palo Alto"
      assert fields["SC-100[0].Page2[0].List1[0].Item1[0].PlaintiffZip1[0]"] == "94303"

      assert fields["SC-100[0].Page2[0].List2[0].item2[0].DefendantName1[0]"] ==
               "Acme Robocallers LLC"

      assert fields["SC-100[0].Page2[0].List2[0].item2[0].DefendantName2[0]"] == "Pat Agent"
      assert fields["SC-100[0].Page2[0].List2[0].item2[0].DefendantCity2[0]"] == "San Francisco"
      assert fields["SC-100[0].Page2[0].List3[0].PlaintiffClaimAmount1[0]"] == "1500.00"
      assert fields["SC-100[0].Page2[0].List3[0].Lia[0].FillField2[0]"] =~ "Do Not Call Registry"
      assert fields["SC-100[0].Page4[0].Sign[0].PlaintiffName1[0]"] == "Jane Doe"

      # Not a public entity, no fee-dispute arbitration, under 12 filings this year.
      assert fields["SC-100[0].Page3[0].List8[0].item8[0].Checkbox61[1]"]
      assert fields["SC-100[0].Page3[0].List7[0].item7[0].Checkbox60[1]"]
      assert fields["SC-100[0].Page4[0].List9[0].Item9[0].Checkbox62[1]"]

      # One violation is $1,500, so the claim is not over $2,500.
      assert fields["SC-100[0].Page4[0].List10[0].li10[0].Checkbox63[1]"]
      refute Map.has_key?(fields, "SC-100[0].Page4[0].List10[0].li10[0].Checkbox63[0]")
    end

    test "SC-100 omits blanks and draft placeholders", %{violations: violations} do
      bare = case_fixture(%{claimant_name: nil, claimant_address: nil})
      fields = OfficialForms.fields("SC-100", Enforcement.get_case!(bare.id), violations)

      refute Enum.any?(Map.values(fields), &(&1 in [nil, ""]))

      refute Enum.any?(Map.values(fields), fn value ->
               is_binary(value) and value =~ ~r/\[.+\]/
             end)
    end

    test "SUM-100 names both parties and serves the entity under CCP 416.10", %{
      case: case_record,
      violations: violations
    } do
      fields = OfficialForms.fields("SUM-100", case_record, violations)

      assert fields["SUM-100[0].Page1[0].Notice[0].FillText25[0]"] == "Acme Robocallers LLC"
      assert fields["SUM-100[0].Page1[0].Notice[0].FillText180[0]"] == "Jane Doe"
      assert fields["SUM-100[0].Page1[0].Info[0].FillText3[0]"] =~ "Superior Court of California"
      assert fields["SUM-100[0].Page1[0].Info[0].FillText2[0]"] =~ "Santa Clara"
      assert fields["SUM-100[0].Page1[0].Info[0].FillText2[0]"] =~ "San Jose, CA 95113"
      assert fields["SUM-100[0].Page1[0].Info[0].FillText30[0]"] =~ "855 Newell Place"

      assert fields[
               "SUM-100[0].Page1[0].Noticeto[0].List[0].Li3[0].SubLi3[0].ServiceSection_cb[0]"
             ]

      refute Map.has_key?(
               fields,
               "SUM-100[0].Page1[0].Noticeto[0].List[0].Li1[0].ServiceDef_cb[0]"
             )
    end

    test "CM-010 marks limited civil, other complaint, and monetary relief", %{
      case: case_record,
      violations: violations
    } do
      limits = DncWatchdog.Enforcement.FilingLimits.civil_assess(length(violations))

      fields =
        OfficialForms.fields("CM-010", case_record, violations, filing_limits: limits)

      assert fields["CM-010[0].Page1[0].P1Caption[0].TitlePartyName[0].Party1[0]"] ==
               "Jane Doe v. Acme Robocallers LLC"

      assert fields["CM-010[0].Page1[0].P1Caption[0].FormTitle[0].Civil[0].limited1[1]"]

      refute Map.has_key?(
               fields,
               "CM-010[0].Page1[0].P1Caption[0].FormTitle[0].Civil[0].limited1[0]"
             )

      assert fields["CM-010[0].Page1[0].List1[0].Item1Check[41]"]
      assert fields["CM-010[0].Page2[0].List3[0].Item3[0].Lia[0].Ch1[0]"]
      assert fields["CM-010[0].Page2[0].SigName[0]"] == "Jane Doe"
      assert fields["CM-010[0].Page1[0].P1Caption[0].AttyPartyInfo[0].AttyFor[0]"] =~ "Pro Per"
    end

    test "CM-010 marks unlimited civil above the limited ceiling", %{
      case: case_record,
      violations: violations
    } do
      limits = DncWatchdog.Enforcement.FilingLimits.civil_assess(30)

      fields = OfficialForms.fields("CM-010", case_record, violations, filing_limits: limits)

      assert fields["CM-010[0].Page1[0].P1Caption[0].FormTitle[0].Civil[0].limited1[0]"]
    end

    @tag :pdf
    test "fill/4 produces a real PDF when the filler is installed", %{
      case: case_record,
      violations: violations
    } do
      if PdfForms.available?() and PdfForms.template_available?("SC-100") do
        assert {:ok, <<"%PDF", _::binary>> = pdf} =
                 OfficialForms.fill("SC-100", case_record, violations)

        assert byte_size(pdf) > 10_000
      end
    end
  end
end

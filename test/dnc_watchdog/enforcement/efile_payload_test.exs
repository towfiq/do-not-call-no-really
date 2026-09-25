defmodule DncWatchdog.Enforcement.EfilePayloadTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.EfilePayload
  import DncWatchdog.EnforcementFixtures

  test "parse_address/1 splits street from city/state/zip" do
    assert EfilePayload.parse_address("123 Oak St\nPalo Alto, CA 94301") == %{
             street: "123 Oak St",
             city: "Palo Alto",
             state: "CA",
             zip: "94301"
           }

    assert EfilePayload.parse_address("500 Market St, San Jose, CA 95113") == %{
             street: "500 Market St",
             city: "San Jose",
             state: "CA",
             zip: "95113"
           }
  end

  test "split_person_name/1 splits first and last" do
    assert EfilePayload.split_person_name("Jane Doe") == %{
             first_name: "Jane",
             last_name: "Doe"
           }
  end

  test "build/2 maps a small-claims case for Odyssey eFileCA" do
    case =
      case_fixture(%{
        claimant_name: "Jane Doe",
        claimant_address: "123 Oak St\nPalo Alto, CA 94301",
        claimant_phone: "4155551212",
        claimant_email: "jane@example.com",
        court_filing_draft: "SMALL CLAIMS PACKET"
      })

    {:ok, case} =
      Enforcement.upsert_case_legal_entity(case, %{
        legal_name: "Acme Robocallers LLC",
        entity_type: "company",
        street: "123 Main St",
        city: "San Francisco",
        state: "ca",
        zip: "94105",
        phone: "4155550000",
        agent_name: "Pat Agent",
        agent_title: "Registered Agent",
        agent_street: "1 Market St",
        agent_city: "San Francisco",
        agent_state: "CA",
        agent_zip: "94105"
      })

    communication_fixture(%{case_id: case.id, violation_status: "violation"})

    payload =
      Enforcement.efile_helper_payload(case, origin: "http://127.0.0.1:4000")

    assert payload.provider == "Odyssey eFileCA"
    assert payload.stop_before_submit
    assert payload.portal_url =~ "california.tylertech.cloud"
    assert payload.venue == "small_claims"
    assert Enum.any?(payload.court.location_hints, &String.contains?(&1, "Santa Clara"))
    assert "Small Claims" in payload.category_hints
    assert payload.plaintiff.first_name == "Jane"
    assert payload.plaintiff.last_name == "Doe"
    assert payload.plaintiff.is_this_party
    refute payload.plaintiff.is_business
    assert payload.plaintiff.address.city == "Palo Alto"
    assert payload.defendant.is_business
    assert payload.defendant.organization_name == "Acme Robocallers LLC"
    assert payload.defendant.phone == "4155550000"
    assert payload.defendant.contact.name == "Pat Agent"
    assert payload.defendant.contact.address.city == "San Francisco"
    assert payload.defendant.address.state == "CA"
    assert payload.defendant.address.country == "United States"
    assert payload.claim_amount == "1500.00"
    lead = hd(payload.documents)
    assert lead.lead?
    assert lead.label =~ "SC-100"
    assert lead.url == "http://127.0.0.1:4000/cases/#{case.id}/forms/sc100.pdf"
    assert "Plaintiff's Claim" in lead.filing_code_hints

    assert Enum.any?(
             payload.documents,
             &(&1.url == "http://127.0.0.1:4000/cases/#{case.id}/court_filing.pdf")
           )

    assert Enum.any?(
             payload.instructions,
             &String.contains?(&1, "Do not let the helper click Submit")
           )
  end

  test "build/2 recommends limited civil and the civil PDF when damages exceed the small-claims cap" do
    case =
      case_fixture(%{
        claimant_name: "Jane Doe",
        civil_complaint_draft: "CIVIL COMPLAINT"
      })

    {:ok, case} =
      Enforcement.upsert_case_legal_entity(case, %{
        legal_name: "Spam Inc",
        street: "1 Market St",
        city: "San Jose",
        state: "CA",
        zip: "95113"
      })

    for i <- 1..10 do
      communication_fixture(%{
        case_id: case.id,
        violation_status: "violation",
        timestamp: NaiveDateTime.add(~N[2026-05-20 09:14:00], i, :day)
      })
    end

    payload = Enforcement.efile_helper_payload(case, origin: "http://127.0.0.1:4000")

    assert payload.venue == "limited_civil"
    assert payload.claim_amount == "15000.00"
    assert hd(payload.documents).label == "Civil complaint packet"
    assert hd(payload.documents).lead?

    supporting = Enum.reject(payload.documents, & &1.lead?)
    assert Enum.map(supporting, & &1.label) |> Enum.any?(&String.starts_with?(&1, "SUM-100"))
    assert Enum.map(supporting, & &1.label) |> Enum.any?(&String.starts_with?(&1, "CM-010"))
  end

  test "build/2 keeps a UK registered office and country for eFileCA" do
    case = case_fixture(%{claimant_name: "Jane Doe", court_filing_draft: "PACKET"})

    {:ok, case} =
      Enforcement.upsert_case_legal_entity(case, %{
        legal_name: "Pathos Communications PLC",
        street: "101 New Cavendish Street, 1st Floor South",
        city: "London",
        state: "England",
        zip: "W1W 6XH",
        country: "GB",
        phone: "3156607625",
        agent_name: "Adam Hurst",
        agent_title: "Company Secretary"
      })

    payload = Enforcement.efile_helper_payload(case)
    assert payload.defendant.organization_name == "Pathos Communications PLC"
    assert payload.defendant.address.city == "London"
    assert payload.defendant.address.state == "England"
    assert payload.defendant.address.country == "United Kingdom"
    assert "United Kingdom" in payload.defendant.address.country_hints
    assert payload.defendant.contact.name == "Adam Hurst"
  end
end

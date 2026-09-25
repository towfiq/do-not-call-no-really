defmodule DncWatchdog.Enforcement.SosLookupTest do
  use ExUnit.Case, async: true

  alias DncWatchdog.Enforcement.LegalEntity
  alias DncWatchdog.Enforcement.SosLookup

  test "search_page/2 uses UK Companies House for British entities" do
    page = SosLookup.search_page("England", "Pathos Communications", country: "GB")
    assert page.name =~ "Companies House"
    assert page.url =~ "company-information.service.gov.uk"
    assert page.url =~ "Pathos"
  end

  test "search_page/2 uses the Illinois SOS business search" do
    page = SosLookup.search_page("il", "Pathos Communications")
    assert page.name =~ "Illinois"
    assert page.url =~ "ilsos.gov"
  end

  test "search_page/2 uses California BizFile" do
    page = SosLookup.search_page("CA", "Acme LLC")
    assert page.url =~ "bizfileonline.sos.ca.gov"
  end

  test "address_lines/1 appends United Kingdom for a British entity" do
    lines =
      LegalEntity.address_lines(%LegalEntity{
        street: "101 New Cavendish Street, 1st Floor South",
        city: "London",
        state: "England",
        zip: "W1W 6XH",
        country: "GB"
      })

    assert lines == [
             "101 New Cavendish Street, 1st Floor South",
             "London, England, W1W 6XH",
             "United Kingdom"
           ]
  end

  test "merge_into_entity/3 keeps an existing mailing address and fills agent + phone" do
    entity = %LegalEntity{
      legal_name: "Pathos Communications",
      street: "600 West Chicago Ave., Suite 150",
      city: "Chicago",
      state: "IL",
      zip: "60654"
    }

    attrs =
      SosLookup.merge_into_entity(
        entity,
        %{
          agent_name: "Jane Agent",
          agent_title: "Registered Agent",
          agent_street: "1 N Wacker",
          agent_city: "Chicago",
          agent_state: "IL",
          agent_zip: "60606",
          street: "999 Other St"
        },
        suggested_phone: "3125550100"
      )

    assert attrs["street"] == nil
    assert attrs["phone"] == "3125550100"
    assert attrs["agent_name"] == "Jane Agent"
    assert attrs["agent_street"] == "1 N Wacker"
    assert attrs["attn"] == "Jane Agent"
    assert attrs["legal_name"] == "Pathos Communications"
  end

  test "pick_california_record/2 matches the entity name" do
    json = %{
      "rows" => %{
        "1" => %{"TITLE" => ["ACME ROBOCALLERS LLC"], "RECORD_NUM" => "2024123"}
      }
    }

    assert {:ok, row} = SosLookup.pick_california_record(json, "Acme Robocallers LLC")
    assert row["RECORD_NUM"] == "2024123"
  end

  test "parse_california_detail/2 reads the registered agent" do
    detail = %{
      "DRAWER_DETAIL_LIST" => [
        %{"LABEL" => "Entity Name", "VALUE" => "ACME ROBOCALLERS LLC"},
        %{"LABEL" => "Agent for Service of Process", "VALUE" => "CT Corporation System"},
        %{"LABEL" => "Agent Street Address", "VALUE" => "330 N Brand Blvd"},
        %{"LABEL" => "Agent City", "VALUE" => "Glendale"},
        %{"LABEL" => "Agent State", "VALUE" => "CA"},
        %{"LABEL" => "Agent Zip", "VALUE" => "91203"}
      ]
    }

    attrs = SosLookup.parse_california_detail(detail, %{})
    assert attrs["agent_name"] == "CT Corporation System"
    assert attrs["agent_street"] == "330 N Brand Blvd"
    assert attrs["source"] == "ca_bizfile"
  end

  test "lookup/3 uses the injected HTTP client for California" do
    search = %{
      "rows" => %{
        "1" => %{"TITLE" => ["ACME ROBOCALLERS LLC"], "RECORD_NUM" => "abc"}
      }
    }

    detail = %{
      "DRAWER_DETAIL_LIST" => [
        %{"LABEL" => "Agent for Service of Process", "VALUE" => "Pat Agent"}
      ]
    }

    client = fn
      :post, url, _headers, _body ->
        assert url =~ "businesssearch"
        {:ok, %{status: 200, body: Jason.encode!(search)}}

      :get, url, _headers, _body ->
        assert url =~ "/abc/"
        {:ok, %{status: 200, body: Jason.encode!(detail)}}
    end

    assert {:ok, attrs} = SosLookup.lookup("Acme Robocallers LLC", "CA", http_client: client)
    assert attrs["agent_name"] == "Pat Agent"
  end
end

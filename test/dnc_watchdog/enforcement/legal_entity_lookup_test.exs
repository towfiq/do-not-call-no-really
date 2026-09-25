defmodule DncWatchdog.Enforcement.LegalEntityLookupTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  import DncWatchdog.EnforcementFixtures

  test "suggested_business_phone/1 uses the most common incoming caller number" do
    case = case_fixture()

    communication_fixture(%{
      case_id: case.id,
      direction: "incoming",
      from_number: "3125550199"
    })

    communication_fixture(%{
      case_id: case.id,
      direction: "incoming",
      from_number: "3125550199"
    })

    communication_fixture(%{
      case_id: case.id,
      direction: "incoming",
      from_number: "8005550000"
    })

    assert Enforcement.suggested_business_phone(case) == "3125550199"
  end

  test "preview_legal_entity_lookup/1 fills phone and points at the state registry" do
    case =
      case_with_legal_entity_fixture(%{}, %{
        legal_name: "Pathos Communications",
        state: "IL",
        city: "Chicago",
        street: "600 West Chicago Ave.",
        zip: "60654"
      })

    communication_fixture(%{
      case_id: case.id,
      direction: "incoming",
      from_number: "3125550199"
    })

    assert {:ok, attrs, meta} = Enforcement.preview_legal_entity_lookup(case)
    assert attrs["phone"] == "3125550199"
    assert attrs["legal_name"] == "Pathos Communications"
    refute meta.found?
    assert meta.search_url =~ "ilsos.gov"
    assert meta.registry_name =~ "Illinois"
  end
end

defmodule DncWatchdog.Enforcement.SearchFilterTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  import DncWatchdog.EnforcementFixtures

  test "list_cases/1 filters by company name search" do
    match = case_fixture(%{company_name: "Acme Robocallers LLC"})
    other = case_fixture(%{company_name: "Other Co"})

    ids =
      Enforcement.list_cases(search: "robocall")
      |> Enum.map(& &1.id)

    assert match.id in ids
    refute other.id in ids
  end

  test "list_cases/1 filters by case id search" do
    case_record = case_fixture(%{company_name: "Id Search Co"})

    ids =
      Enforcement.list_cases(search: "#{case_record.id}")
      |> Enum.map(& &1.id)

    assert case_record.id in ids
  end

  test "list_cases/1 filters by incoming phone on linked communications" do
    case_record = case_fixture(%{company_name: "Phone Match Co"})

    communication_fixture(%{
      case_id: case_record.id,
      from_number: "+1 (555) 867-5309",
      direction: "incoming"
    })

    ids =
      Enforcement.list_cases(search: "8675309")
      |> Enum.map(& &1.id)

    assert case_record.id in ids
  end

  test "list_cases/1 filters by message body text" do
    match = case_fixture(%{company_name: "Caller 6506293859"})
    other = case_fixture(%{company_name: "Caller 8001234567"})

    communication_fixture(%{
      case_id: match.id,
      body: "Hey ELLA, this is Tina with Sandium.",
      violation_status: "excluded"
    })

    communication_fixture(%{
      case_id: other.id,
      body: "Limited time car warranty",
      violation_status: "pending"
    })

    ids =
      Enforcement.list_cases(search: "tina")
      |> Enum.map(& &1.id)

    assert match.id in ids
    refute other.id in ids
  end

  test "list_cases/1 filters by legal entity name" do
    match = case_with_legal_entity_fixture(%{company_name: "Caller 9254996086"})
    other = case_fixture(%{company_name: "Caller 8001234567"})

    ids =
      Enforcement.list_cases(search: "equinox")
      |> Enum.map(& &1.id)

    assert match.id in ids
    refute other.id in ids
  end

  test "list_communications/1 filters by message body" do
    case_record = case_fixture()
    match = communication_fixture(%{case_id: case_record.id, body: "unique violation phrase"})
    other = communication_fixture(%{case_id: case_record.id, body: "hello there"})

    ids =
      Enforcement.list_communications(search: "violation phrase", hide_excluded: false)
      |> Enum.map(& &1.id)

    assert match.id in ids
    refute other.id in ids
  end

  test "list_communications/1 filters by linked case company name" do
    case_record = case_fixture(%{company_name: "Zeta Marketing Inc"})
    comm = communication_fixture(%{case_id: case_record.id, body: "generic text"})

    ids =
      Enforcement.list_communications(search: "zeta marketing", hide_excluded: false)
      |> Enum.map(& &1.id)

    assert comm.id in ids
  end

  test "list_communications/1 filters by email from_number" do
    case_record = case_fixture()
    match = communication_fixture(%{case_id: case_record.id, from_number: "mom@example.com"})
    other = communication_fixture(%{case_id: case_record.id, from_number: "8009990000"})

    ids =
      Enforcement.list_communications(search: "mom@example.com", hide_excluded: false)
      |> Enum.map(& &1.id)

    assert match.id in ids
    refute other.id in ids
  end

  test "search combines with workflow phase filter" do
    visible = case_fixture(%{company_name: "Sent Acme Co", workflow_step: "sent"})
    wrong_phase = case_fixture(%{company_name: "Intake Acme Co", workflow_step: "intake"})

    ids =
      Enforcement.list_cases(search: "acme", workflow_phase: "sent")
      |> Enum.map(& &1.id)

    assert visible.id in ids
    refute wrong_phase.id in ids
  end
end

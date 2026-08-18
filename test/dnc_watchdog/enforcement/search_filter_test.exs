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

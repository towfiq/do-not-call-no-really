defmodule DncWatchdog.Enforcement.CaseGroupsTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.CaseGroups
  alias DncWatchdog.Repo

  import DncWatchdog.EnforcementFixtures

  test "link_cases/2 groups communications on case show queries" do
    case_a = case_fixture(%{company_name: "Caller 8024329794"})
    case_b = case_fixture(%{company_name: "Caller 8029928875"})

    {:ok, comm_a} =
      Enforcement.create_communication(
        communication_attrs(%{case_id: case_a.id, from_number: "8024329794", body: "June text"})
      )

    {:ok, comm_b} =
      Enforcement.create_communication(
        communication_attrs(%{case_id: case_b.id, from_number: "8029928875", body: "February text"})
      )

    assert {:ok, _} = CaseGroups.link_cases(case_a, case_b)

    ids = CaseGroups.case_ids_for_group(case_a.id) |> MapSet.new()
    assert MapSet.equal?(ids, MapSet.new([case_a.id, case_b.id]))

    combined = Enforcement.list_case_communications(case_a.id)
    assert length(combined) == 2
    assert Enum.map(combined, & &1.id) |> MapSet.new() == MapSet.new([comm_a.id, comm_b.id])
  end

  test "merge_case_into/2 moves communications and deletes the source case" do
    target = case_fixture(%{company_name: "Caller 8024329794"})
    source = case_fixture(%{company_name: "Caller 8029928875"})

    {:ok, comm} =
      Enforcement.create_communication(
        communication_attrs(%{case_id: source.id, from_number: "8029928875", body: "Merged text"})
      )

    assert {:ok, updated_target} = CaseGroups.merge_case_into(target, source.id)
    assert updated_target.id == target.id
    refute Repo.get(DncWatchdog.Enforcement.Case, source.id)

    [moved] = Enforcement.list_case_communications(target.id)
    assert moved.id == comm.id
    assert moved.case_id == target.id
  end

  test "search_linkable_cases/2 matches company name and phone" do
    case_a = case_fixture(%{company_name: "Caller A"})
    case_b = case_fixture(%{company_name: "Caller 8029928875"})
    case_c = case_fixture(%{company_name: "Unrelated LLC"})

    {:ok, _} =
      Enforcement.create_communication(
        communication_attrs(%{case_id: case_c.id, from_number: "8029928875", body: "text"})
      )

    results = Enforcement.search_linkable_cases(case_a, "8029928875")
    result_ids = Enum.map(results, & &1.id) |> MapSet.new()
    assert MapSet.equal?(result_ids, MapSet.new([case_b.id, case_c.id]))

    assert Enum.any?(Enforcement.search_linkable_cases(case_a, "802992"), &(&1.company_name == "Caller 8029928875"))

    refute Enum.any?(Enforcement.search_linkable_cases(case_a, "Unrelated"), &(&1.id == case_a.id))
  end

  test "unlink_case/1 stops grouping communications" do
    case_a = case_fixture(%{company_name: "Caller A"})
    case_b = case_fixture(%{company_name: "Caller B"})
    {:ok, _} = CaseGroups.link_cases(case_a, case_b)

    Enforcement.create_communication(communication_attrs(%{case_id: case_b.id}))
    assert length(Enforcement.list_case_communications(case_a.id)) == 1

    case_b = Enforcement.get_case!(case_b.id)
    {:ok, _} = CaseGroups.unlink_case(case_b)
    assert Enforcement.list_case_communications(case_a.id) == []
  end
end

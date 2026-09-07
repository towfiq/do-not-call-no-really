defmodule DncWatchdog.Enforcement.OwnNumberTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.RowImporter
  import DncWatchdog.EnforcementFixtures

  setup do
    {:ok, _} = Enforcement.update_claimant_profile(%{phone: "4159719595"})
    :ok
  end

  test "reconcile does not collapse unrelated incoming onto the owner's phone" do
    own_case = case_fixture(%{company_name: "Caller 4159719595"})
    spam_case = case_fixture(%{company_name: "Caller 8001234567"})

    communication_fixture(%{
      case_id: own_case.id,
      direction: "incoming",
      from_number: "4159719595",
      to_number: "4159719595",
      body: "from myself"
    })

    communication_fixture(%{
      case_id: spam_case.id,
      direction: "incoming",
      from_number: "8001234567",
      to_number: "4159719595",
      body: "car warranty"
    })

    assert %{reassigned: 0} = Enforcement.reconcile_incoming_peer_case_assignments()
    assert length(Enforcement.list_case_communications(spam_case.id)) == 1
    assert length(Enforcement.list_case_communications(own_case.id)) == 1
  end

  test "import_row/1 skips incoming rows from the owner's phone" do
    row =
      import_row_attrs(%{
        company: "",
        from_number: "4159719595",
        to_number: "4159719595",
        direction: "incoming"
      })

    assert {:ok, :skipped_own_number} = RowImporter.import_row(row)
    assert Enforcement.list_cases() == []
    assert Enforcement.count_communications() == 0
  end

  test "import_rows/1 counts skipped own-number rows" do
    rows = [
      import_row_attrs(%{from_number: "4159719595", to_number: "4159719595", company: ""}),
      import_row_attrs(%{from_number: "8001234567", to_number: "4159719595", company: ""})
    ]

    summary = RowImporter.import_rows(rows)

    assert summary.skipped_own_number == 1
    assert summary.created_communications == 1
    assert [%{company_name: "Caller 8001234567"}] = Enforcement.list_cases()
  end

  test "unwind_own_number_case_assignments/0 restores callers onto their own cases" do
    collapsed = case_fixture(%{company_name: "Caller 4159719595"})
    existing = case_fixture(%{company_name: "Caller 8001112222"})

    self_comm =
      communication_fixture(%{
        case_id: collapsed.id,
        from_number: "4159719595",
        to_number: "4159719595",
        body: "self"
      })

    keep_on_existing =
      communication_fixture(%{
        case_id: collapsed.id,
        from_number: "8001112222",
        to_number: "4159719595",
        body: "existing peer"
      })

    needs_new_case =
      communication_fixture(%{
        case_id: collapsed.id,
        from_number: "8003334444",
        to_number: "4159719595",
        body: "new peer"
      })

    summary = Enforcement.unwind_own_number_case_assignments()

    assert summary.reassigned == 2
    assert summary.created_cases == 1
    assert summary.deleted_own_communications == 1
    assert summary.deleted_own_cases == 1

    refute DncWatchdog.Repo.get(DncWatchdog.Enforcement.Communication, self_comm.id)
    refute DncWatchdog.Repo.get(DncWatchdog.Enforcement.Case, collapsed.id)

    assert DncWatchdog.Repo.get!(DncWatchdog.Enforcement.Communication, keep_on_existing.id).case_id ==
             existing.id

    new_case =
      Enforcement.list_cases()
      |> Enum.find(&(&1.company_name == "Caller 8003334444"))

    assert new_case

    assert DncWatchdog.Repo.get!(DncWatchdog.Enforcement.Communication, needs_new_case.id).case_id ==
             new_case.id
  end

  test "merge does not steal incoming just because to_number is the owner's phone" do
    target = case_fixture(%{company_name: "Caller 9495390557"})
    source = case_fixture(%{company_name: "Caller 9494682993"})
    other = case_fixture(%{company_name: "Caller 8001234567"})

    {:ok, source_comm} =
      Enforcement.create_communication(
        communication_attrs(%{
          case_id: source.id,
          from_number: "9494682993",
          to_number: "4159719595",
          body: "on source"
        })
      )

    {:ok, other_comm} =
      Enforcement.create_communication(
        communication_attrs(%{
          case_id: other.id,
          from_number: "8001234567",
          to_number: "4159719595",
          body: "unrelated inbox"
        })
      )

    assert {:ok, _} = Enforcement.merge_case_into(target, source.id)

    assert DncWatchdog.Repo.get!(DncWatchdog.Enforcement.Communication, source_comm.id).case_id ==
             target.id

    assert DncWatchdog.Repo.get!(DncWatchdog.Enforcement.Communication, other_comm.id).case_id ==
             other.id
  end
end

defmodule DncWatchdog.EnforcementTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement

  describe "cases" do
    alias DncWatchdog.Enforcement.Case

    import DncWatchdog.EnforcementFixtures

    @invalid_attrs %{status: nil, company_name: nil, workflow_step: nil}

    test "list_cases/0 returns all cases" do
      case = case_fixture()
      assert Enforcement.list_cases() == [case]
    end

    test "list_cases/1 with require_violations only returns cases with violations" do
      visible = case_fixture(%{company_name: "Violation Co"})
      hidden = case_fixture(%{company_name: "Pending Only Co"})
      communication_fixture(%{case_id: visible.id, violation_status: "violation"})

      ids = Enforcement.list_cases(require_violations: true) |> Enum.map(& &1.id)
      assert visible.id in ids
      refute hidden.id in ids
    end

    test "get_case!/1 returns the case with given id" do
      case = case_fixture()
      fetched = Enforcement.get_case!(case.id)
      assert fetched.id == case.id
    end

    test "create_case/1 with valid data creates a case" do
      valid_attrs = %{status: "new", company_name: "some company_name", workflow_step: "intake", notes: "some notes", letter_draft: "some letter_draft"}

      assert {:ok, %Case{} = case} = Enforcement.create_case(valid_attrs)
      assert case.status == "new"
      assert case.company_name == "some company_name"
      assert case.workflow_step == "intake"
      assert case.notes == "some notes"
      assert case.letter_draft == "some letter_draft"
    end

    test "create_case/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Enforcement.create_case(@invalid_attrs)
    end

    test "update_case/2 with valid data updates the case" do
      case = case_fixture()
      update_attrs = %{status: "investigating", company_name: "some updated company_name", workflow_step: "triage", notes: "some updated notes", letter_draft: "some updated letter_draft"}

      assert {:ok, %Case{} = case} = Enforcement.update_case(case, update_attrs)
      assert case.status == "investigating"
      assert case.company_name == "some updated company_name"
      assert case.workflow_step == "triage"
      assert case.notes == "some updated notes"
      assert case.letter_draft == "some updated letter_draft"
    end

    test "update_case/2 with invalid data returns error changeset" do
      case = case_fixture()
      assert {:error, %Ecto.Changeset{}} = Enforcement.update_case(case, @invalid_attrs)
      assert case.id == Enforcement.get_case!(case.id).id
    end

    test "delete_case/1 deletes the case" do
      case = case_fixture()
      assert {:ok, %Case{}} = Enforcement.delete_case(case)
      assert_raise Ecto.NoResultsError, fn -> Enforcement.get_case!(case.id) end
    end

    test "change_case/1 returns a case changeset" do
      case = case_fixture()
      assert %Ecto.Changeset{} = Enforcement.change_case(case)
    end
  end
end

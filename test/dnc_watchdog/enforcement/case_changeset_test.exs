defmodule DncWatchdog.Enforcement.CaseChangesetTest do
  use DncWatchdog.DataCase, async: true

  alias DncWatchdog.Enforcement.Case

  test "valid changeset accepts allowed status and workflow_step" do
    changeset =
      Case.changeset(%Case{}, %{
        company_name: "Acme",
        status: "new",
        workflow_step: "intake"
      })

    assert changeset.valid?
  end

  test "invalid status is rejected" do
    changeset =
      Case.changeset(%Case{}, %{
        company_name: "Acme",
        status: "bogus",
        workflow_step: "intake"
      })

    refute changeset.valid?
    assert %{status: [_ | _]} = errors_on(changeset)
  end

  test "invalid workflow_step is rejected" do
    changeset =
      Case.changeset(%Case{}, %{
        company_name: "Acme",
        status: "new",
        workflow_step: "bogus"
      })

    refute changeset.valid?
    assert %{workflow_step: [_ | _]} = errors_on(changeset)
  end

  test "company_name is required" do
    changeset = Case.changeset(%Case{}, %{status: "new", workflow_step: "intake"})
    refute changeset.valid?
    assert %{company_name: [_ | _]} = errors_on(changeset)
  end
end

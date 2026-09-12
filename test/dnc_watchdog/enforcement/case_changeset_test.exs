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

  test "settled status and workflow_step are accepted" do
    changeset =
      Case.changeset(%Case{}, %{
        company_name: "Acme",
        status: "settled",
        workflow_step: "settled"
      })

    assert changeset.valid?
  end

  test "company_name is required" do
    changeset = Case.changeset(%Case{}, %{status: "new", workflow_step: "intake"})
    refute changeset.valid?
    assert %{company_name: [_ | _]} = errors_on(changeset)
  end

  test "display_name/1 prefers legal entity name" do
    entity = %DncWatchdog.Enforcement.LegalEntity{legal_name: "Equinox Roofing LLC"}

    assert Case.display_name(%Case{company_name: "Caller 9254996086", legal_entity: entity}) ==
             "Equinox Roofing LLC"
  end

  test "display_name/1 falls back to company_name" do
    assert Case.display_name(%Case{company_name: "Caller 9254996086"}) == "Caller 9254996086"
  end
end

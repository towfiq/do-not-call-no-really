defmodule DncWatchdog.Enforcement.WorkflowTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  import DncWatchdog.EnforcementFixtures

  test "advance_case_workflow/1 blocks evidence_review without violations and address" do
    case = case_fixture(%{workflow_step: "evidence_review"})

    assert {:error, messages} = Enforcement.advance_case_workflow(case)
    assert Enum.any?(messages, &String.contains?(&1, "violation"))
    assert Enum.any?(messages, &String.contains?(&1, "address"))
  end

  test "advance_case_workflow/1 moves to draft_review when requirements met" do
    case = case_fixture(%{workflow_step: "evidence_review", letter_draft: ""})

    {:ok, case} =
      Enforcement.upsert_case_legal_entity(case, %{
        legal_name: "Acme LLC",
        street: "1 Main",
        city: "SF",
        state: "CA",
        zip: "94105"
      })

    communication_fixture(%{case_id: case.id, violation_status: "violation"})

    Enforcement.create_evidence_attachment!(%{
      case_id: case.id,
      filename: "proof.png",
      storage_path: "uploads/evidence/1/proof.png"
    })

    assert {:ok, updated} = Enforcement.advance_case_workflow(case)
    assert updated.workflow_step == "draft_review"
  end

  test "advance_case_workflow/1 moves sent to delivered" do
    case = case_fixture(%{workflow_step: "sent", status: "sent"})

    assert {:ok, updated} = Enforcement.advance_case_workflow(case)
    assert updated.workflow_step == "delivered"
    assert updated.status == "delivered"
  end
end

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

  test "settle_case/1 marks the case settled without advancing to trial" do
    case = case_fixture(%{workflow_step: "delivered", status: "delivered"})

    assert {:ok, updated} = Enforcement.settle_case(case)
    assert updated.workflow_step == "settled"
    assert updated.status == "settled"
  end

  test "before?/2 compares workflow order" do
    assert Enforcement.Workflow.before?("intake", "delivered")
    assert Enforcement.Workflow.before?("sent", "delivered")
    refute Enforcement.Workflow.before?("delivered", "delivered")
    refute Enforcement.Workflow.before?("litigation_draft", "delivered")
    refute Enforcement.Workflow.before?("draft_review", "intake")
  end

  test "generate_letter_draft/1 advances workflow to draft_review when behind" do
    case = case_fixture(%{workflow_step: "triage", letter_draft: nil})

    assert {:ok, updated} = Enforcement.generate_letter_draft(case)
    assert updated.letter_draft not in [nil, ""]
    assert updated.workflow_step == "draft_review"
    assert updated.status == "drafting_letter"
  end

  test "generate_letter_draft/1 does not move workflow backward" do
    case = case_fixture(%{workflow_step: "sent", status: "sent", letter_draft: nil})

    assert {:ok, updated} = Enforcement.generate_letter_draft(case)
    assert updated.workflow_step == "sent"
    assert updated.status == "sent"
  end

  test "save_letter_draft/2 advances workflow to draft_review when behind" do
    case = case_fixture(%{workflow_step: "intake", letter_draft: nil})

    assert {:ok, updated} = Enforcement.save_letter_draft(case, "Demand letter body")
    assert updated.letter_draft == "Demand letter body"
    assert updated.workflow_step == "draft_review"
    assert updated.status == "drafting_letter"
  end
end

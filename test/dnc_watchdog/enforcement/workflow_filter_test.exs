defmodule DncWatchdog.Enforcement.WorkflowFilterTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  import DncWatchdog.EnforcementFixtures

  test "list_cases/1 filters by workflow phase" do
    intake = case_fixture(%{company_name: "Intake Co", workflow_step: "intake"})
    sent = case_fixture(%{company_name: "Sent Co", workflow_step: "sent"})
    litigation = case_fixture(%{company_name: "Lit Co", workflow_step: "litigation_draft"})

    triage_ids =
      Enforcement.list_cases(workflow_phase: "triage")
      |> Enum.map(& &1.id)

    assert intake.id in triage_ids
    refute sent.id in triage_ids
    refute litigation.id in triage_ids

    sent_ids = Enforcement.list_cases(workflow_phase: "sent") |> Enum.map(& &1.id)
    assert sent.id in sent_ids
    refute intake.id in sent_ids

    delivered =
      case_fixture(%{
        company_name: "Delivered Co",
        workflow_step: "delivered",
        status: "delivered"
      })

    delivered_ids = Enforcement.list_cases(workflow_phase: "delivered") |> Enum.map(& &1.id)
    assert delivered.id in delivered_ids
    refute sent.id in delivered_ids

    litigation_ids = Enforcement.list_cases(workflow_phase: "litigation") |> Enum.map(& &1.id)
    assert litigation.id in litigation_ids
    refute sent.id in litigation_ids

    settled =
      case_fixture(%{
        company_name: "Settled Co",
        workflow_step: "settled",
        status: "settled"
      })

    settled_ids = Enforcement.list_cases(workflow_phase: "settled") |> Enum.map(& &1.id)
    assert settled.id in settled_ids
    refute litigation.id in settled_ids
    refute sent.id in settled_ids
  end

  test "list_communications/1 filters by linked case workflow phase" do
    intake_case = case_fixture(%{workflow_step: "intake"})
    sent_case = case_fixture(%{workflow_step: "sent"})

    intake_comm =
      communication_fixture(%{
        case_id: intake_case.id,
        from_number: "8001111111",
        body: "intake msg"
      })

    _sent_comm =
      communication_fixture(%{
        case_id: sent_case.id,
        from_number: "8002222222",
        body: "sent msg"
      })

    triage_comms = Enforcement.list_communications(workflow_phase: "triage", hide_excluded: false)
    assert Enum.any?(triage_comms, &(&1.id == intake_comm.id))
    refute Enum.any?(triage_comms, &(&1.body == "sent msg"))

    sent_comms = Enforcement.list_communications(workflow_phase: "sent", hide_excluded: false)
    assert Enum.any?(sent_comms, &(&1.body == "sent msg"))
    refute Enum.any?(sent_comms, &(&1.id == intake_comm.id))
  end
end

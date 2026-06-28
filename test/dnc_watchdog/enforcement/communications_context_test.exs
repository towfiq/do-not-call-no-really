defmodule DncWatchdog.Enforcement.CommunicationsContextTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  import DncWatchdog.EnforcementFixtures

  test "create_communication/1 persists row" do
    attrs = communication_attrs()
    assert {:ok, comm} = Enforcement.create_communication(attrs)
    assert comm.channel == "sms"
    assert comm.case_id == attrs.case_id
  end

  test "list_case_communications/1 orders newest first" do
    attrs = communication_attrs()

    {:ok, older} =
      Enforcement.create_communication(Map.put(attrs, :timestamp, ~N[2026-05-19 09:00:00]))

    {:ok, newer} =
      Enforcement.create_communication(Map.put(attrs, :timestamp, ~N[2026-05-21 09:00:00]))

    assert [^newer, ^older] = Enforcement.list_case_communications(attrs.case_id)
  end

  test "list_cases/1 can preload communications" do
    comm = communication_fixture()
    [case_record] = Enforcement.list_cases(preload_communications: true)
    assert length(case_record.communications) == 1
    assert hd(case_record.communications).id == comm.id
  end
end

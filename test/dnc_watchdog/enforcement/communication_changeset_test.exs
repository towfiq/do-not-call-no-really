defmodule DncWatchdog.Enforcement.CommunicationChangesetTest do
  use DncWatchdog.DataCase, async: true

  alias DncWatchdog.Enforcement.Communication

  test "valid communication changeset" do
    changeset =
      Communication.changeset(%Communication{}, %{
        timestamp: ~N[2026-05-20 09:14:00],
        channel: "sms",
        direction: "incoming",
        from_number: "8001234567",
        to_number: "5550001234"
      })

    assert changeset.valid?
  end

  test "rejects invalid channel" do
    changeset =
      Communication.changeset(%Communication{}, %{
        timestamp: ~N[2026-05-20 09:14:00],
        channel: "email",
        direction: "incoming",
        from_number: "1",
        to_number: "2"
      })

    refute changeset.valid?
    assert %{channel: [_ | _]} = errors_on(changeset)
  end

  test "accepts exempt as a violation status" do
    changeset =
      Communication.changeset(%Communication{}, %{
        timestamp: ~N[2026-05-20 09:14:00],
        channel: "call",
        direction: "incoming",
        from_number: "8001234567",
        to_number: "5550001234",
        violation_status: "exempt"
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :violation_status) == "exempt"
  end

  test "rejects invalid direction" do
    changeset =
      Communication.changeset(%Communication{}, %{
        timestamp: ~N[2026-05-20 09:14:00],
        channel: "call",
        direction: "sideways",
        from_number: "1",
        to_number: "2"
      })

    refute changeset.valid?
    assert %{direction: [_ | _]} = errors_on(changeset)
  end
end

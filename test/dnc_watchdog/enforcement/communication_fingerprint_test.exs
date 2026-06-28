defmodule DncWatchdog.Enforcement.CommunicationFingerprintTest do
  use ExUnit.Case, async: true

  alias DncWatchdog.Enforcement.Communication

  test "fingerprint ignores to_number for incoming rows" do
    base = %{
      timestamp: ~N[2026-02-03 18:53:26],
      channel: "sms",
      direction: "incoming",
      from_number: "8029928875",
      duration_seconds: 0,
      body: "Hi Mark, this is Cherry with TKPG."
    }

    with_local = Map.put(base, :to_number, "local")
    with_phone = Map.put(base, :to_number, "4159719595")

    assert Communication.fingerprint(with_local) == Communication.fingerprint(with_phone)
  end

  test "fingerprint ignores from_number for outgoing rows" do
    base = %{
      timestamp: ~N[2026-02-03 18:53:26],
      channel: "sms",
      direction: "outgoing",
      to_number: "8029928875",
      duration_seconds: 0,
      body: "No thanks"
    }

    with_local = Map.put(base, :from_number, "local")
    with_phone = Map.put(base, :from_number, "4159719595")

    assert Communication.fingerprint(with_local) == Communication.fingerprint(with_phone)
  end
end

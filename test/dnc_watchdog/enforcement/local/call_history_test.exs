defmodule DncWatchdog.Enforcement.Local.CallHistoryTest do
  use ExUnit.Case, async: true

  alias DncWatchdog.Enforcement.Local.CallHistory
  alias DncWatchdog.SqliteFixtures

  setup do
    dir = SqliteFixtures.temp_dir!()
    on_exit(fn -> File.rm_rf(dir) end)
    path = Path.join(dir, "CallHistory.storedata")
    SqliteFixtures.create_call_history_db(path)
    %{path: path}
  end

  test "read/2 parses ZCALLRECORD rows", %{path: path} do
    assert {:ok, [row]} = CallHistory.read(path, limit: 5, my_phone: "5550001234")

    assert row.channel == "call"
    assert row.direction == "incoming"
    assert row.from_number == "8009998888"
    assert row.duration_seconds == 8
    assert row.company == "Robo Warranty Co"
  end

  test "read/2 returns error for missing database" do
    assert {:error, message} = CallHistory.read("/no/such/CallHistory.storedata")
    assert message =~ "not found"
  end
end

defmodule DncWatchdog.Enforcement.Local.LookbackTest do
  use ExUnit.Case, async: true

  alias DncWatchdog.Enforcement.Local.Lookback

  test "since_from_opts/1 with lookback_days" do
    since = Lookback.since_from_opts(lookback_days: 7)
    assert %NaiveDateTime{} = since
    assert NaiveDateTime.compare(since, NaiveDateTime.utc_now()) in [:lt, :eq]
  end

  test "filter_rows/2 removes rows before since" do
    since = ~N[2026-06-01 00:00:00]

    rows = [
      %{timestamp: ~N[2026-05-31 12:00:00]},
      %{timestamp: ~N[2026-06-02 12:00:00]}
    ]

    {kept, skipped} = Lookback.filter_rows(rows, since)
    assert length(kept) == 1
    assert skipped == 1
  end

  test "messages_where_fragment/1 distinguishes seconds from nanoseconds" do
    since = ~N[2026-06-01 00:00:00]
    sql = Lookback.messages_where_fragment(since)

    refute sql =~ "OR m.date >="
    assert sql =~ "1000000000000"
    assert sql =~ Integer.to_string(Lookback.min_apple_seconds(since))
    assert sql =~ Integer.to_string(Lookback.min_apple_nanoseconds(since))
  end

  test "sql_limit_clause/2 skips cap when lookback is set" do
    since = ~N[2026-06-01 00:00:00]
    assert Lookback.sql_limit_clause(since, 5_000) == ""
    assert Lookback.sql_limit_clause(nil, 5_000) == "LIMIT 5000"
  end
end

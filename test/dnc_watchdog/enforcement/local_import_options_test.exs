defmodule DncWatchdog.Enforcement.LocalImportOptionsTest do
  use ExUnit.Case, async: true

  alias DncWatchdog.Enforcement.LocalImportOptions

  test "build/1 drops limit when lookback_days is set" do
    opts = LocalImportOptions.build(lookback_days: 180, limit: 50)

    assert opts[:lookback_days] == 180
    assert %NaiveDateTime{} = opts[:since]
    assert opts[:limit] == nil
    assert LocalImportOptions.sql_row_cap(lookback_days: 180, limit: 50) == :no_cap
  end

  test "build/1 keeps limit when no lookback is set" do
    opts = LocalImportOptions.build(limit: 50)

    assert opts[:since] == nil
    assert opts[:limit] == 50
    assert LocalImportOptions.sql_row_cap(limit: 50) == 50
  end
end

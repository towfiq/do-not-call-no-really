defmodule DncWatchdog.Enforcement.ContactCacheTest do
  use ExUnit.Case, async: false

  alias DncWatchdog.Enforcement.ContactCache

  test "get_set/0 returns a contact set map" do
    set = ContactCache.get_set()
    assert is_map(set)
    assert Map.has_key?(set, :phones)
    assert Map.has_key?(set, :emails)
  end
end

defmodule DncWatchdog.Enforcement.PhoneTest do
  use ExUnit.Case, async: true

  alias DncWatchdog.Enforcement.Phone

  test "normalize/1 handles nil and formats US numbers" do
    assert Phone.normalize(nil) == ""
    assert Phone.normalize("+1 (800) 123-4567") == "8001234567"
  end

  test "normalize_or_env/1 falls back to empty string when unset" do
    assert Phone.normalize_or_env(nil) == System.get_env("DNC_MY_PHONE") || ""
    assert Phone.normalize_or_env("+1-555-000-1234") == "5550001234"
  end

  test "lookup_keys/1 indexes US numbers with and without country code 1" do
    assert Enum.sort(Phone.lookup_keys("+1 (800) 123-4567")) == ["18001234567", "8001234567"]
    assert Enum.sort(Phone.lookup_keys("8001234567")) == ["18001234567", "8001234567"]
    assert Enum.sort(Phone.lookup_keys("+18001234567")) == ["18001234567", "8001234567"]
  end

  test "contact_member?/2 matches +1 contacts against 10-digit message peers" do
    phones = MapSet.new(Phone.lookup_keys("+1-818-743-2556"))

    assert Phone.contact_member?("8187432556", phones)
    assert Phone.contact_member?("+18187432556", phones)
    refute Phone.contact_member?("9999999999", phones)
  end
end

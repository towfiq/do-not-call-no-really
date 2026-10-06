defmodule DncWatchdog.Enforcement.MacosPermissionsTest do
  use ExUnit.Case, async: true

  alias DncWatchdog.Enforcement.MacosPermissions

  test "app_name/0 defaults to Dnc Watchdog" do
    assert MacosPermissions.app_name() == "Dnc Watchdog"
  end

  test "full_disk_access_instructions/0 references the app name" do
    assert MacosPermissions.full_disk_access_instructions() =~ "Dnc Watchdog"
    assert MacosPermissions.full_disk_access_instructions() =~ "Full Disk Access"
  end

  test "launch_hint/0 mentions the macOS app bundle" do
    assert MacosPermissions.launch_hint() =~ "macos/DncWatchdog.app"
  end
end

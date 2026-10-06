defmodule DncWatchdog.Enforcement.MacosPermissions do
  @moduledoc """
  macOS Full Disk Access guidance for local Messages, Call History, and Contacts import.

  Grant permissions to **Dnc Watchdog** by launching `macos/DncWatchdog.app`, not your
  editor or terminal.
  """

  @default_app_name "Dnc Watchdog"

  @doc "Application name shown in System Settings → Full Disk Access."
  def app_name do
    System.get_env("DNC_FDA_APP_NAME") || @default_app_name
  end

  @doc """
  Standard instruction for enabling Full Disk Access.
  """
  def full_disk_access_instructions do
    "Grant Full Disk Access to #{app_name()} in System Settings → Privacy & Security → Full Disk Access, then restart #{app_name()}."
  end

  @doc """
  Reminder to launch via the macOS app bundle so permissions apply to this project.
  """
  def launch_hint do
    "Launch with `open macos/DncWatchdog.app` so macOS applies permissions to #{app_name()}, not your editor."
  end

  @doc """
  Prefix a failure reason with Full Disk Access guidance.
  """
  def permission_error(prefix) when is_binary(prefix) do
    String.trim("#{prefix} #{full_disk_access_instructions()}")
  end
end

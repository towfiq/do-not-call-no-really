defmodule DncWatchdogWeb.SettingsLiveTest do
  use DncWatchdogWeb.ConnCase

  import Phoenix.LiveViewTest

  alias DncWatchdog.Enforcement

  test "saves claimant profile", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    view
    |> form("#claimant-profile-form", claimant_profile: %{name: "Jane Doe", address: "123 Main"})
    |> render_submit()

    profile = Enforcement.get_claimant_profile()
    assert profile.name == "Jane Doe"
    assert profile.address == "123 Main"
  end

  test "shows Chrome helper install path", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/settings")
    assert html =~ "USPS Chrome helper"
    assert html =~ "Load unpacked"
    assert html =~ "chrome_extension"
    assert html =~ "Browser helper connected"
  end

  test "shows Safari helper Xcode project", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/settings")
    assert html =~ "USPS Safari helper"
    assert html =~ "safari_extension"
    assert html =~ "DNCWatchdogUspsHelper.xcodeproj"
    assert html =~ "Allow unsigned extensions"
    assert html =~ "Open in Xcode"
  end
end

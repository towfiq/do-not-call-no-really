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
end

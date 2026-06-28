defmodule DncWatchdogWeb.ExcludedSenderLiveTest do
  use DncWatchdogWeb.ConnCase

  import Phoenix.LiveViewTest

  alias DncWatchdog.Enforcement

  test "lists excluded senders and removes one", %{conn: conn} do
    {:ok, _sender} = Enforcement.add_excluded_sender("8005550000")

    {:ok, view, html} = live(conn, ~p"/excluded-senders")
    assert html =~ "8005550000"

    view |> element("button", "Remove") |> render_click()

    html = render(view)
    refute html =~ "8005550000"
    refute Enforcement.excluded_sender?("8005550000")
  end
end

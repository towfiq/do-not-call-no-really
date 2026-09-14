defmodule DncWatchdogWeb.ExcludedSenderLiveTest do
  use DncWatchdogWeb.ConnCase

  import Phoenix.LiveViewTest
  import DncWatchdog.EnforcementFixtures

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

  test "links each sender to their messages including excluded rows", %{conn: conn} do
    communication_fixture(%{
      from_number: "8005550000",
      body: "excluded sender review token",
      violation_status: "pending"
    })

    {:ok, _} = Enforcement.exclude_all_from_peer("8005550000")

    {:ok, _view, html} = live(conn, ~p"/excluded-senders")
    assert html =~ "View messages"
    assert html =~ "Damages"
    assert html =~ "$1,500.00"
    assert html =~ "Total"
    assert html =~ ~s(href="/communications?)
    assert html =~ "q=8005550000"
    assert html =~ "include_excluded=true"
    assert html =~ "include_contacts=true"

    {:ok, _messages_view, messages_html} =
      live(
        conn,
        ~p"/communications?#{[q: "8005550000", peer: "8005550000", include_excluded: true, include_contacts: true]}"
      )

    assert messages_html =~ "excluded sender review token"
    assert messages_html =~ "8005550000"
  end

  test "sorts and filters excluded senders by communication count", %{conn: conn} do
    communication_fixture(%{
      from_number: "8005551001",
      violation_status: "excluded",
      body: "solo excluded"
    })

    {:ok, _} = Enforcement.add_excluded_sender("8005551001")

    for i <- 1..3 do
      communication_fixture(%{
        from_number: "8005551002",
        violation_status: "excluded",
        body: "repeat excluded #{i}"
      })
    end

    {:ok, _} = Enforcement.add_excluded_sender("8005551002")

    {:ok, view, html} = live(conn, ~p"/excluded-senders")
    assert html =~ "8005551001"
    assert html =~ "8005551002"
    assert html =~ "Communications"

    html =
      view
      |> form("#excluded-min-comms-filter", %{"min_comms" => "2"})
      |> render_change()

    refute html =~ "8005551001"
    assert html =~ "8005551002"

    {:ok, view, _html} = live(conn, ~p"/excluded-senders")

    html =
      view
      |> element("#sort-excluded-senders-communications")
      |> render_click()

    {many_at, _} = :binary.match(html, "8005551002")
    {one_at, _} = :binary.match(html, "8005551001")
    assert many_at < one_at
  end
end

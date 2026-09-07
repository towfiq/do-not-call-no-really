defmodule DncWatchdogWeb.CommunicationLiveTest do
  use DncWatchdogWeb.ConnCase

  import Phoenix.LiveViewTest
  import DncWatchdog.EnforcementFixtures

  alias DncWatchdog.Enforcement

  test "grouped view titles sender peer not linked case name", %{conn: conn} do
    case = case_fixture(%{company_name: "Caller 4159719595"})

    communication_fixture(%{
      case_id: case.id,
      from_number: "639283296146",
      direction: "incoming",
      body: "DMV spam test",
      violation_status: "pending"
    })

    {:ok, _view, html} = live(conn, ~p"/communications")

    assert html =~ "639283296146"
    assert html =~ "Caller 4159719595"
    refute html =~ ~r/<h2[^>]*>Caller 4159719595<\/h2>/
  end

  test "shows legal entity name for linked case", %{conn: conn} do
    case =
      case_with_legal_entity_fixture(%{
        company_name: "Caller 9254996086"
      })

    communication_fixture(%{
      case_id: case.id,
      body: "legal entity display test",
      violation_status: "violation"
    })

    {:ok, _view, html} = live(conn, ~p"/communications")

    assert html =~ "Equinox Roofing LLC"
    assert html =~ "legal entity display test"
  end

  test "lists imported communications with message body", %{conn: conn} do
    communication_fixture(%{body: "Hello from import test", violation_status: "violation"})

    {:ok, _view, html} = live(conn, ~p"/communications")

    assert html =~ "Messages"
    assert html =~ "Hello from import test"
    assert html =~ "Group by sender"
    assert html =~ "Include spam"
    assert html =~ "Include excluded"
    assert html =~ "Include known contacts"
    assert html =~ "Apply filters"
    assert html =~ "Sync from Mac"
    assert html =~ "Since last sync"
    assert html =~ "Last 30 days"
    assert html =~ "Last sync: Never synced"
  end

  test "sync lookback selection is retained for sync_local", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/communications")

    html =
      view
      |> form("#sync-lookback-form", %{
        "lookback_days" => "30",
        "include_contacts" => "true"
      })
      |> render_change()

    assert html =~ ~s(value="30")
    assert html =~ "Include contacts"
  end

  test "sync_local submit reads include_contacts from the form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/communications")

    # Submit without a prior change event — options must come from the form payload.
    view
    |> form("#sync-lookback-form", %{
      "lookback_days" => "7",
      "include_contacts" => "true"
    })
    |> render_submit()

    assigns = :sys.get_state(view.pid).socket.assigns
    assert assigns.sync_lookback_days == 7
    assert assigns.sync_include_contacts
  end

  test "mark spam and hide spam filter work independently of excluded sender", %{conn: conn} do
    spam_target = communication_fixture(%{from_number: "8001112222", body: "mark me"})
    communication_fixture(%{from_number: "8003334444", body: "keep me"})

    {:ok, view, _html} = live(conn, ~p"/communications")

    view
    |> element("#spam-#{spam_target.id}")
    |> render_click()

    html = render(view)
    assert html =~ "Marked as spam"
    assert html =~ "Unspam"
    assert html =~ "Spam"

    html =
      view
      |> form("#display-filters", %{
        "filters" => %{
          "violations_only" => "false",
          "include_excluded" => "false",
          "group_by_sender" => "true",
          "include_spam" => "false"
        }
      })
      |> render_submit()

    refute html =~ "mark me"
    assert html =~ "keep me"
  end

  test "group by sender filter shows sender sections", %{conn: conn} do
    communication_fixture(%{
      from_number: "8001112222",
      body: "spam one",
      violation_status: "violation"
    })

    communication_fixture(%{
      from_number: "8001112222",
      body: "spam two",
      violation_status: "violation"
    })

    communication_fixture(%{
      from_number: "8009990000",
      body: "other line",
      violation_status: "violation"
    })

    {:ok, view, html} = live(conn, ~p"/communications")

    assert html =~ "8001112222"
    assert html =~ "8009990000"
    assert html =~ "spam one"

    html =
      view
      |> form("#display-filters", %{
        "filters" => %{
          "violations_only" => "false",
          "include_excluded" => "false",
          "group_by_sender" => "false",
          "include_spam" => "true"
        }
      })
      |> render_submit()

    refute html =~ "2 communication(s)"
    assert html =~ "spam one"
  end

  test "hide excluded filter removes non-violations", %{conn: conn} do
    communication_fixture(%{violation_status: "violation", body: "spam offer"})
    communication_fixture(%{violation_status: "excluded", body: "friend hello"})

    {:ok, _view, html} = live(conn, ~p"/communications")
    assert html =~ "spam offer"
    refute html =~ "friend hello"
  end

  test "exclude sender marks all communications from the same number", %{conn: conn} do
    first =
      communication_fixture(%{
        from_number: "8001112222",
        violation_status: "pending",
        body: "spam 1"
      })

    communication_fixture(%{
      from_number: "8001112222",
      violation_status: "violation",
      body: "spam 2"
    })

    communication_fixture(%{
      from_number: "8009990000",
      violation_status: "pending",
      body: "other"
    })

    {:ok, view, _html} = live(conn, ~p"/communications")

    view
    |> element("#exclude-sender-#{first.id}")
    |> render_click()

    html = render(view)
    refute html =~ "spam 1"
    refute html =~ "spam 2"
    assert html =~ "other"

    assert html =~
             "Marked 2 communication(s) from 8001112222 as not a violation; sender saved for future imports"

    assert Enforcement.count_communications(hide_excluded: true) == 1
  end

  test "filters communications by linked case workflow phase", %{conn: conn} do
    {:ok, intake_case} =
      Enforcement.create_case(%{
        company_name: "Intake",
        status: "new",
        workflow_step: "intake",
        letter_draft: ""
      })

    {:ok, sent_case} =
      Enforcement.create_case(%{
        company_name: "Sent",
        status: "sent",
        workflow_step: "sent",
        letter_draft: ""
      })

    communication_fixture(%{case_id: intake_case.id, body: "intake only"})
    communication_fixture(%{case_id: sent_case.id, body: "sent only"})

    {:ok, view, html} = live(conn, ~p"/communications?workflow=sent")

    assert html =~ "sent only"
    refute html =~ "intake only"

    html =
      view
      |> form("#display-filters", %{
        "filters" => %{
          "violations_only" => "false",
          "include_excluded" => "false",
          "group_by_sender" => "true",
          "include_spam" => "true",
          "workflow" => "triage"
        }
      })
      |> render_submit()

    assert html =~ "intake only"
    refute html =~ "sent only"
  end

  test "filters communications by search query", %{conn: conn} do
    case_record = case_fixture()
    communication_fixture(%{case_id: case_record.id, body: "special search token"})
    communication_fixture(%{case_id: case_record.id, body: "ordinary message"})

    {:ok, view, html} = live(conn, ~p"/communications?q=search+token")

    assert html =~ "special search token"
    refute html =~ "ordinary message"

    html =
      view
      |> form("#communications-search", %{q: ""})
      |> render_change()

    assert html =~ "special search token"
    assert html =~ "ordinary message"
  end

  test "search includes excluded messages", %{conn: conn} do
    case_record = case_fixture()

    communication_fixture(%{
      case_id: case_record.id,
      body: "Hey ELLA, this is Tina with Sandium.",
      violation_status: "excluded"
    })

    {:ok, _view, html} = live(conn, ~p"/communications?q=tina")

    assert html =~ "Tina with Sandium"
  end
end

defmodule DncWatchdogWeb.CaseLiveTest do
  use DncWatchdogWeb.ConnCase

  import Phoenix.LiveViewTest
  import DncWatchdog.EnforcementFixtures

  @create_attrs %{
    status: "new",
    company_name: "some company_name",
    workflow_step: "intake",
    notes: "some notes",
    letter_draft: "some letter_draft"
  }
  @update_attrs %{
    status: "investigating",
    company_name: "some updated company_name",
    workflow_step: "triage",
    notes: "some updated notes",
    letter_draft: "some updated letter_draft"
  }
  @invalid_attrs %{status: "new", company_name: nil, workflow_step: "intake"}

  defp create_case(_) do
    case = case_fixture()
    communication_fixture(%{case_id: case.id, violation_status: "violation"})
    %{case: case}
  end

  describe "Index" do
    setup [:create_case]

    test "lists all cases", %{conn: conn, case: case} do
      {:ok, _index_live, html} = live(conn, ~p"/cases")

      assert html =~ "Listing Cases"
      assert html =~ case.status
    end

    test "saves new case", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/cases")

      assert index_live |> element("a", "New Case") |> render_click() =~
               "New Case"

      assert_patch(index_live, ~p"/cases/new")

      create_attrs = Map.put(@create_attrs, :company_name, "Brand New Case Co")

      assert index_live
             |> form("#case-form", case: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#case-form", case: create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/cases")

      html = render(index_live)
      assert html =~ "Case created successfully"
      refute html =~ "Brand New Case Co"
    end

    test "updates case in listing", %{conn: conn, case: case} do
      {:ok, index_live, _html} = live(conn, ~p"/cases")

      assert index_live |> element("#cases-#{case.id} a", "Edit") |> render_click() =~
               "Edit Case"

      assert_patch(index_live, ~p"/cases/#{case}/edit")

      assert index_live
             |> form("#case-form", case: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#case-form", case: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/cases")

      html = render(index_live)
      assert html =~ "Case updated successfully"
      assert html =~ "investigating"
    end

    test "deletes case in listing", %{conn: conn, case: case} do
      {:ok, index_live, _html} = live(conn, ~p"/cases")

      assert index_live |> element("#cases-#{case.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#cases-#{case.id}")
    end

    test "filters cases by workflow phase", %{conn: conn} do
      visible =
        case_fixture(%{company_name: "Visible Sent Co", workflow_step: "sent", status: "sent"})

      communication_fixture(%{case_id: visible.id, violation_status: "violation"})
      _hidden = case_fixture(%{company_name: "Hidden Intake Co", workflow_step: "intake"})

      {:ok, view, html} = live(conn, ~p"/cases?workflow=sent")

      assert html =~ "Visible Sent Co"
      refute html =~ "Hidden Intake Co"

      html =
        view
        |> element("button", "All")
        |> render_click()

      assert html =~ "Visible Sent Co"
      refute html =~ "Hidden Intake Co"
    end

    test "shows legal entity name in Defendant column", %{conn: conn} do
      case =
        case_with_legal_entity_fixture(%{
          company_name: "Caller 9254996086"
        })

      communication_fixture(%{case_id: case.id, violation_status: "violation"})

      {:ok, _view, html} = live(conn, ~p"/cases")

      assert html =~ "Equinox Roofing LLC"
      refute html =~ "Caller 9254996086"
    end

    test "filters cases by search query", %{conn: conn} do
      match = case_fixture(%{company_name: "Searchable Widgets LLC"})
      communication_fixture(%{case_id: match.id, violation_status: "violation"})
      _other = case_fixture(%{company_name: "Unrelated Corp"})

      {:ok, view, html} = live(conn, ~p"/cases?q=widget")

      assert html =~ "Searchable Widgets LLC"
      refute html =~ "Unrelated Corp"
      assert html =~ "matching"

      html =
        view
        |> form("#cases-search", %{q: ""})
        |> render_change()

      assert html =~ "Searchable Widgets LLC"
      refute html =~ "Unrelated Corp"
    end

    test "filters cases by message body even without violations", %{conn: conn} do
      match = case_fixture(%{company_name: "Caller 6506293859"})

      communication_fixture(%{
        case_id: match.id,
        body: "Hey ELLA, this is Tina with Sandium.",
        violation_status: "excluded"
      })

      {:ok, _view, html} = live(conn, ~p"/cases?q=tina")

      assert html =~ "Caller 6506293859"
      assert html =~ "matching"
    end
  end

  describe "Show" do
    setup [:create_case]

    test "displays case", %{conn: conn, case: case} do
      {:ok, _show_live, html} = live(conn, ~p"/cases/#{case}")

      assert html =~ "Show Case"
      assert html =~ case.status
    end

    test "displays communications with case link", %{conn: conn, case: case} do
      {:ok, _show_live, html} = live(conn, ~p"/cases/#{case}")

      assert html =~ "communications-case-#{case.id}"
      assert html =~ case.company_name
    end

    test "apply_filters controls visible communications", %{conn: conn, case: case} do
      communication_fixture(%{
        case_id: case.id,
        violation_status: "excluded",
        body: "excluded msg"
      })

      communication_fixture(%{case_id: case.id, violation_status: "pending", body: "pending msg"})

      {:ok, view, html} = live(conn, ~p"/cases/#{case}")

      assert html =~ "Limited time offer"
      assert html =~ "pending msg"
      refute html =~ "excluded msg"

      html =
        view
        |> form("#case-display-filters", %{
          "filters" => %{
            "violations_only" => "true",
            "include_excluded" => "false"
          }
        })
        |> render_submit()

      assert html =~ "Limited time offer"
      refute html =~ "pending msg"
      refute html =~ "excluded msg"

      html =
        view
        |> form("#case-display-filters", %{
          "filters" => %{
            "violations_only" => "false",
            "include_excluded" => "true"
          }
        })
        |> render_submit()

      assert html =~ "Limited time offer"
      assert html =~ "pending msg"
      assert html =~ "excluded msg"
    end

    test "advances workflow step", %{conn: conn, case: case} do
      {:ok, view, _html} = live(conn, ~p"/cases/#{case}")

      view |> element("button", "Advance workflow") |> render_click()

      updated = DncWatchdog.Enforcement.get_case!(case.id)
      assert updated.workflow_step == "triage"
      assert updated.status == "investigating"
    end

    test "marks case as settled", %{conn: conn, case: case} do
      {:ok, view, html} = live(conn, ~p"/cases/#{case}")

      assert html =~ "Mark as settled"

      view |> element("button", "Mark as settled") |> render_click()

      html = render(view)
      assert html =~ "Case marked as settled"
      refute html =~ "Mark as settled"
      refute html =~ "Advance workflow"

      updated = DncWatchdog.Enforcement.get_case!(case.id)
      assert updated.workflow_step == "settled"
      assert updated.status == "settled"
    end

    test "updates case within modal", %{conn: conn, case: case} do
      {:ok, show_live, _html} = live(conn, ~p"/cases/#{case}")

      assert show_live |> element("a", "Edit case") |> render_click() =~
               "Edit Case"

      assert_patch(show_live, ~p"/cases/#{case}/show/edit")

      assert show_live
             |> form("#case-form", case: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#case-form", case: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/cases/#{case}")

      html = render(show_live)
      assert html =~ "Case updated successfully"
      assert html =~ "investigating"
    end

    test "saves letter draft", %{conn: conn, case: case} do
      {:ok, view, _html} = live(conn, ~p"/cases/#{case}")

      draft = "Updated demand letter body with edits."

      view
      |> form("#letter-draft-form", letter_draft: %{body: draft})
      |> render_submit()

      html = render(view)
      assert html =~ "Letter draft saved. Workflow moved to draft review."
      assert html =~ draft

      updated = DncWatchdog.Enforcement.get_case!(case.id)
      assert updated.letter_draft == draft
      assert updated.workflow_step == "draft_review"
    end

    test "saves mail tracking number", %{conn: conn, case: case} do
      {:ok, view, html} = live(conn, ~p"/cases/#{case}")

      assert html =~ "Certified mail tracking"

      view
      |> form("#mail-tracking-form",
        mail_tracking: %{tracking_number: "9400 1118 9922 3197 4284 90"}
      )
      |> render_submit()

      html = render(view)
      assert html =~ "Tracking number saved"
      assert html =~ "9400111899223197428490"
      assert html =~ "Not checked yet"

      updated = DncWatchdog.Enforcement.get_case!(case.id)
      assert updated.mail_tracking_number == "9400111899223197428490"
      assert updated.mail_delivery_status == "pending"
    end

    test "refreshes mail tracking from the Chrome helper", %{conn: conn, case: case} do
      DncWatchdog.Enforcement.UspsBrowserHelper.reset()

      {:ok, case} =
        DncWatchdog.Enforcement.save_mail_tracking_number(case, "9400111899223197428490")

      {:ok, view, _html} = live(conn, ~p"/cases/#{case}")

      view |> element("#refresh-mail-tracking-button") |> render_click()

      html = render(view)
      assert html =~ "Waiting for Chrome helper"
      assert html =~ "Wait for the Chrome helper"
      assert_push_event(view, "open_usps_helper", %{url: url})
      assert url =~ "9400111899223197428490"

      helper_conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/usps_helper",
          Jason.encode!(%{
            "tracking_number" => "9400111899223197428490",
            "text" => "Tracking History Your item was delivered, May 1, 2026 at 3:14 pm.",
            "summary" => "Your item was delivered, May 1, 2026 at 3:14 pm.",
            "title" => "USPS Tracking"
          })
        )

      assert json_response(helper_conn, 200)["ok"] == true

      html = wait_for_html(view, "Tracking updated")
      assert html =~ "Tracking updated"
      assert html =~ "delivered"
      assert html =~ "Save status to this case"
      assert html =~ "Close"
    end

    test "shows helper parse errors in the progress dialog", %{conn: conn, case: case} do
      DncWatchdog.Enforcement.UspsBrowserHelper.reset()

      {:ok, case} =
        DncWatchdog.Enforcement.save_mail_tracking_number(case, "9400111899223197428490")

      {:ok, view, _html} = live(conn, ~p"/cases/#{case}")

      view |> element("#refresh-mail-tracking-button") |> render_click()

      helper_conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/usps_helper",
          Jason.encode!(%{
            "tracking_number" => "9400111899223197428490",
            "blocked" => true,
            "text" => "Access Denied",
            "summary" => "USPS blocked automated access"
          })
        )

      assert json_response(helper_conn, 422)

      html = wait_for_html(view, "Tracking check failed")
      assert html =~ "Tracking check failed"
      assert html =~ "USPS blocked"
      assert html =~ "Read tracking status"
      assert html =~ "Try headless Chrome"
    end

    test "falls back to headless Chrome from the progress panel", %{conn: conn, case: case} do
      previous = Application.get_env(:dnc_watchdog, :usps_tracking, [])

      Application.put_env(:dnc_watchdog, :usps_tracking,
        page_fetcher: DncWatchdog.Enforcement.UspsTracking.StubPageFetcher
      )

      on_exit(fn -> Application.put_env(:dnc_watchdog, :usps_tracking, previous) end)
      DncWatchdog.Enforcement.UspsBrowserHelper.reset()

      {:ok, case} =
        DncWatchdog.Enforcement.save_mail_tracking_number(case, "9400111899223197428490")

      {:ok, view, _html} = live(conn, ~p"/cases/#{case}")

      view |> element("#refresh-mail-tracking-button") |> render_click()

      helper_conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/usps_helper",
          Jason.encode!(%{
            "tracking_number" => "9400111899223197428490",
            "blocked" => true,
            "summary" => "USPS blocked automated access"
          })
        )

      assert json_response(helper_conn, 422)

      html = wait_for_html(view, "Try headless Chrome")
      assert html =~ "Try headless Chrome"

      view |> element("#refresh-mail-tracking-headless-button") |> render_click()

      html = render_async(view)
      assert html =~ "Tracking updated"
      assert html =~ "Load USPS tracking page"
    end

    test "searches linkable cases as you type", %{conn: conn, case: case} do
      other = case_fixture(%{company_name: "Caller 8029928875"})

      {:ok, view, _html} = live(conn, ~p"/cases/#{case}")

      html =
        view
        |> form("#link-case-search", query: "8029928875")
        |> render_change()

      assert html =~ other.company_name
      assert html =~ "Case #{other.id}"
    end
  end

  defp wait_for_html(view, text, attempts \\ 20) do
    html = render(view)

    cond do
      html =~ text ->
        html

      attempts <= 1 ->
        html

      true ->
        Process.sleep(25)
        wait_for_html(view, text, attempts - 1)
    end
  end
end

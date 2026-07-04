defmodule DncWatchdogWeb.CaseLiveTest do
  use DncWatchdogWeb.ConnCase

  import Phoenix.LiveViewTest
  import DncWatchdog.EnforcementFixtures

  @create_attrs %{status: "new", company_name: "some company_name", workflow_step: "intake", notes: "some notes", letter_draft: "some letter_draft"}
  @update_attrs %{status: "investigating", company_name: "some updated company_name", workflow_step: "triage", notes: "some updated notes", letter_draft: "some updated letter_draft"}
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

    test "filters cases by search query", %{conn: conn} do
      match = case_fixture(%{company_name: "Searchable Widgets LLC"})
      communication_fixture(%{case_id: match.id, violation_status: "violation"})
      _other = case_fixture(%{company_name: "Unrelated Corp"})

      {:ok, view, html} = live(conn, ~p"/cases?q=widget")

      assert html =~ "Searchable Widgets LLC"
      refute html =~ "Unrelated Corp"

      html =
        view
        |> form("#cases-search", %{q: ""})
        |> render_change()

      assert html =~ "Searchable Widgets LLC"
      refute html =~ "Unrelated Corp"
    end
  end

  describe "Show" do
    setup [:create_case]

    test "displays case", %{conn: conn, case: case} do
      {:ok, _show_live, html} = live(conn, ~p"/cases/#{case}")

      assert html =~ "Show Case"
      assert html =~ case.status
    end

    test "advances workflow step", %{conn: conn, case: case} do
      {:ok, view, _html} = live(conn, ~p"/cases/#{case}")

      view |> element("button", "Advance workflow") |> render_click()

      updated = DncWatchdog.Enforcement.get_case!(case.id)
      assert updated.workflow_step == "triage"
      assert updated.status == "investigating"
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
      assert html =~ "Letter draft saved"
      assert html =~ draft

      updated = DncWatchdog.Enforcement.get_case!(case.id)
      assert updated.letter_draft == draft
    end

    test "saves mail tracking number", %{conn: conn, case: case} do
      {:ok, view, html} = live(conn, ~p"/cases/#{case}")

      assert html =~ "Certified mail tracking"

      view
      |> form("#mail-tracking-form", mail_tracking: %{tracking_number: "9400 1118 9922 3197 4284 90"})
      |> render_submit()

      html = render(view)
      assert html =~ "Tracking number saved"
      assert html =~ "9400111899223197428490"
      assert html =~ "Not checked yet"

      updated = DncWatchdog.Enforcement.get_case!(case.id)
      assert updated.mail_tracking_number == "9400111899223197428490"
      assert updated.mail_delivery_status == "pending"
    end

    test "refreshes mail tracking asynchronously", %{conn: conn, case: case} do
      previous = Application.get_env(:dnc_watchdog, :usps_tracking, [])

      Application.put_env(:dnc_watchdog, :usps_tracking,
        page_fetcher: DncWatchdog.Enforcement.UspsTracking.StubPageFetcher
      )

      on_exit(fn -> Application.put_env(:dnc_watchdog, :usps_tracking, previous) end)

      {:ok, case} = DncWatchdog.Enforcement.save_mail_tracking_number(case, "9400111899223197428490")
      {:ok, view, _html} = live(conn, ~p"/cases/#{case}")

      view |> element("button", "Refresh status") |> render_click()

      html = render_async(view)
      assert html =~ "Tracking updated"
      assert html =~ "delivered"
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
end

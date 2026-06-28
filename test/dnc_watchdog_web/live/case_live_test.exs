defmodule DncWatchdogWeb.CaseLiveTest do
  use DncWatchdogWeb.ConnCase

  import Phoenix.LiveViewTest
  import DncWatchdog.EnforcementFixtures

  @create_attrs %{status: "new", company_name: "some company_name", workflow_step: "intake", notes: "some notes", letter_draft: "some letter_draft"}
  @update_attrs %{status: "investigating", company_name: "some updated company_name", workflow_step: "triage", notes: "some updated notes", letter_draft: "some updated letter_draft"}
  @invalid_attrs %{status: "new", company_name: nil, workflow_step: "intake"}

  defp create_case(_) do
    case = case_fixture()
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

      assert index_live
             |> form("#case-form", case: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#case-form", case: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/cases")

      html = render(index_live)
      assert html =~ "Case created successfully"
      assert html =~ "new"
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

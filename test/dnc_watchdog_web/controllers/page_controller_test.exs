defmodule DncWatchdogWeb.PageControllerTest do
  use DncWatchdogWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Do Not Call Enforcement"
  end
end

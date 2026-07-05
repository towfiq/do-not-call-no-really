defmodule DncWatchdogWeb.PageControllerTest do
  use DncWatchdogWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Dashboard"
  end
end

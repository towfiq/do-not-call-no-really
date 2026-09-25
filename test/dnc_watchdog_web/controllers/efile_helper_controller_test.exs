defmodule DncWatchdogWeb.EfileHelperControllerTest do
  use DncWatchdogWeb.ConnCase

  import DncWatchdog.EnforcementFixtures

  test "returns an eFileCA helper payload", %{conn: conn} do
    case = case_fixture(%{claimant_name: "Jane Doe", court_filing_draft: "packet"})

    conn = get(conn, ~p"/api/cases/#{case.id}/efile_helper")
    body = json_response(conn, 200)

    assert body["provider"] == "Odyssey eFileCA"
    assert body["stop_before_submit"] == true
    assert body["case_id"] == case.id
    assert body["plaintiff"]["first_name"] == "Jane"
  end
end

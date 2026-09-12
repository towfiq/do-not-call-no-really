defmodule DncWatchdogWeb.UspsHelperControllerTest do
  use DncWatchdogWeb.ConnCase, async: false

  import DncWatchdog.EnforcementFixtures

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.UspsBrowserHelper

  setup do
    UspsBrowserHelper.reset()
    :ok
  end

  test "returns 409 when no refresh is waiting", %{conn: conn} do
    conn = post_helper(conn, helper_payload("9400111899223197428490"))
    assert json_response(conn, 409)["error"] == "no_pending_lookup"
  end

  test "saves a pending helper page", %{conn: conn} do
    case =
      case_fixture(%{workflow_step: "sent", status: "sent"})
      |> then(fn c ->
        {:ok, c} = Enforcement.save_mail_tracking_number(c, "9400111899223197428490")
        c
      end)

    :ok = UspsBrowserHelper.register(case.mail_tracking_number, case.id)

    conn = post_helper(conn, helper_payload(case.mail_tracking_number))
    assert json_response(conn, 200)["ok"] == true

    updated = Enforcement.get_case!(case.id)
    assert updated.mail_delivery_status == "delivered"
  end

  defp post_helper(conn, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/api/usps_helper", Jason.encode!(payload))
  end

  defp helper_payload(number) do
    %{
      "tracking_number" => number,
      "text" => "Tracking History Your item was delivered, May 1, 2026 at 3:14 pm.",
      "summary" => "Your item was delivered, May 1, 2026 at 3:14 pm.",
      "title" => "USPS Tracking",
      "url" => "https://tools.usps.com/go/TrackConfirmAction?qtc_tLabels1=#{number}"
    }
  end
end

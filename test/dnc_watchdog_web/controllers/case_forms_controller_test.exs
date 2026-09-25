defmodule DncWatchdogWeb.CaseFormsControllerTest do
  use DncWatchdogWeb.ConnCase

  import DncWatchdog.EnforcementFixtures

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.PdfForms

  setup do
    case_record =
      case_fixture(%{
        claimant_name: "Jane Doe",
        claimant_address: "855 Newell Place\nPalo Alto, CA 94303",
        claimant_phone: "4159719595"
      })

    {:ok, case_record} =
      Enforcement.upsert_case_legal_entity(case_record, %{
        legal_name: "Acme Robocallers LLC",
        street: "1 Market St",
        city: "San Jose",
        state: "CA",
        zip: "95113"
      })

    %{case: case_record}
  end

  test "downloads a filled SC-100", %{conn: conn, case: case_record} do
    communication_fixture(%{case_id: case_record.id, violation_status: "violation"})

    if PdfForms.available?() do
      conn = get(conn, ~p"/cases/#{case_record.id}/forms/sc100.pdf")

      assert response_content_type(conn, :pdf) =~ "application/pdf"
      assert <<"%PDF", _::binary>> = response(conn, 200)
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "sc100.pdf"
    end
  end

  test "asks for violations before filling forms", %{conn: conn, case: case_record} do
    conn = get(conn, ~p"/cases/#{case_record.id}/forms/sc100.pdf")

    assert redirected_to(conn) == ~p"/cases/#{case_record.id}"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Mark at least one violation"
  end

  test "rejects forms this app does not fill", %{conn: conn, case: case_record} do
    communication_fixture(%{case_id: case_record.id, violation_status: "violation"})

    conn = get(conn, ~p"/cases/#{case_record.id}/forms/fl100.pdf")

    assert redirected_to(conn) == ~p"/cases/#{case_record.id}"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not one of the forms"
  end
end

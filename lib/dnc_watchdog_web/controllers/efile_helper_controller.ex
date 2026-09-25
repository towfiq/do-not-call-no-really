defmodule DncWatchdogWeb.EfileHelperController do
  use DncWatchdogWeb, :controller

  alias DncWatchdog.Enforcement

  def options(conn, _params) do
    conn
    |> put_cors()
    |> send_resp(204, "")
  end

  def show(conn, %{"id" => id}) do
    conn = put_cors(conn)
    case_record = Enforcement.get_case!(id)
    origin = DncWatchdogWeb.Endpoint.url()

    json(conn, Enforcement.efile_helper_payload(case_record, origin: origin))
  end

  defp put_cors(conn) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-headers", "content-type")
    |> put_resp_header("access-control-allow-methods", "GET, OPTIONS")
  end
end

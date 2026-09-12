defmodule DncWatchdogWeb.UspsHelperController do
  use DncWatchdogWeb, :controller

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.UspsBrowserHelper
  alias DncWatchdog.Enforcement.UspsTracking

  def options(conn, _params) do
    conn
    |> put_cors()
    |> send_resp(204, "")
  end

  def create(conn, params) do
    conn = put_cors(conn)

    case Enforcement.apply_usps_helper_page(params) do
      {:ok, case_record} ->
        broadcast(case_record.id, {:ok, case_record})

        json(conn, %{
          ok: true,
          delivery_status: case_record.mail_delivery_status
        })

      {:error, :not_pending} ->
        conn
        |> put_status(:conflict)
        |> json(%{ok: false, error: "no_pending_lookup"})

      {:error, {:helper_failed, case_id, reason}} ->
        broadcast(case_id, {:error, reason})

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: UspsTracking.error_message(reason)})
    end
  end

  defp broadcast(case_id, result) do
    Phoenix.PubSub.broadcast(
      DncWatchdog.PubSub,
      UspsBrowserHelper.topic(case_id),
      {:usps_helper_result, result}
    )
  end

  defp put_cors(conn) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-headers", "content-type")
    |> put_resp_header("access-control-allow-methods", "POST, OPTIONS")
  end
end

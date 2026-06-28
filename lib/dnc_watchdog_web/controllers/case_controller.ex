defmodule DncWatchdogWeb.CaseController do
  use DncWatchdogWeb, :controller

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.LetterExporter
  alias DncWatchdog.Enforcement.LetterPdf

  def letter_pdf(conn, %{"id" => id}) do
    case_record = Enforcement.get_case!(id)

    cond do
      case_record.letter_draft in [nil, ""] ->
        conn
        |> put_flash(:error, "Generate a letter draft before downloading PDF.")
        |> redirect(to: ~p"/cases/#{case_record}")

      true ->
        attachments = Enforcement.list_case_attachments(case_record.id)

        case LetterPdf.generate(case_record.letter_draft, attachments) do
          {:ok, pdf} ->
            filename = "#{LetterExporter.safe_company_filename(case_record.company_name)}_demand_letter.pdf"

            conn
            |> put_resp_content_type("application/pdf")
            |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
            |> send_resp(200, pdf)

          {:error, reason} ->
            conn
            |> put_flash(:error, pdf_error_message(reason))
            |> redirect(to: ~p"/cases/#{case_record}")
        end
    end
  end

  defp pdf_error_message(:chromic_pdf_unavailable) do
    "PDF export is not loaded. Stop the server, run `mix deps.get && mix compile`, then restart with `mix phx.server`."
  end

  defp pdf_error_message(:chromic_pdf_not_started) do
    "PDF export failed to start. Restart the server after installing Google Chrome or Chromium."
  end

  defp pdf_error_message(reason) do
    "Could not generate PDF (#{inspect(reason)}). Install Google Chrome or Chromium for PDF export."
  end
end

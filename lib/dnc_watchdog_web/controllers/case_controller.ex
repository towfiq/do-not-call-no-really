defmodule DncWatchdogWeb.CaseController do
  use DncWatchdogWeb, :controller

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.LetterExporter
  alias DncWatchdog.Enforcement.LetterPdf
  alias DncWatchdog.Enforcement.OfficialForms

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
            filename =
              "#{LetterExporter.safe_company_filename(case_record.company_name)}_demand_letter.pdf"

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

  def court_filing_pdf(conn, %{"id" => id}) do
    case_record = Enforcement.get_case!(id)

    cond do
      case_record.court_filing_draft in [nil, ""] ->
        conn
        |> put_flash(:error, "Generate a court filing draft before downloading PDF.")
        |> redirect(to: ~p"/cases/#{case_record}")

      true ->
        attachments = Enforcement.list_case_attachments(case_record.id)

        case LetterPdf.generate(case_record.court_filing_draft, attachments) do
          {:ok, pdf} ->
            filename =
              "#{LetterExporter.safe_company_filename(case_record.company_name)}_small_claims_filing.pdf"

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

  def civil_complaint_pdf(conn, %{"id" => id}) do
    case_record = Enforcement.get_case!(id)

    cond do
      case_record.civil_complaint_draft in [nil, ""] ->
        conn
        |> put_flash(:error, "Generate a civil complaint draft before downloading PDF.")
        |> redirect(to: ~p"/cases/#{case_record}")

      true ->
        attachments = Enforcement.list_case_attachments(case_record.id)

        case LetterPdf.generate(case_record.civil_complaint_draft, attachments) do
          {:ok, pdf} ->
            filename =
              "#{LetterExporter.safe_company_filename(case_record.company_name)}_civil_complaint.pdf"

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

  def official_form_pdf(conn, %{"id" => id, "code" => requested}) do
    case_record = Enforcement.get_case!(id)
    code = OfficialForms.code_from_filename(requested)

    case code && Enforcement.official_form_pdf(case_record, code) do
      {:ok, pdf} ->
        send_pdf(conn, pdf, filename(case_record, OfficialForms.filename(code)))

      {:error, reason} ->
        conn
        |> put_flash(:error, form_error_message(reason))
        |> redirect(to: ~p"/cases/#{case_record}")

      nil ->
        conn
        |> put_flash(:error, form_error_message({:unknown_form, requested}))
        |> redirect(to: ~p"/cases/#{case_record}")
    end
  end

  def filing_packet_pdf(conn, %{"id" => id}) do
    case_record = Enforcement.get_case!(id)

    with {:ok, narrative} <- narrative_pdf(case_record),
         {:ok, pdf} <- Enforcement.official_packet_pdf(case_record, narrative) do
      send_pdf(conn, pdf, filename(case_record, "filing_packet"))
    else
      {:error, reason} ->
        conn
        |> put_flash(:error, form_error_message(reason))
        |> redirect(to: ~p"/cases/#{case_record}")
    end
  end

  defp narrative_pdf(case_record) do
    draft = case_record.civil_complaint_draft || case_record.court_filing_draft

    if draft in [nil, ""] do
      {:ok, nil}
    else
      attachments = Enforcement.list_case_attachments(case_record.id)
      LetterPdf.generate(draft, attachments)
    end
  end

  defp send_pdf(conn, pdf, filename) do
    conn
    |> put_resp_content_type("application/pdf")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, pdf)
  end

  defp filename(case_record, "" <> name) do
    if String.ends_with?(name, ".pdf") do
      "#{LetterExporter.safe_company_filename(case_record.company_name)}_#{name}"
    else
      "#{LetterExporter.safe_company_filename(case_record.company_name)}_#{name}.pdf"
    end
  end

  defp form_error_message(:no_violations) do
    "Mark at least one violation before generating court forms."
  end

  defp form_error_message(:form_filler_unavailable) do
    "The PDF form filler is not installed. Run `mix dnc.setup_forms` to create priv/form_filler/.venv."
  end

  defp form_error_message({:template_missing, code}) do
    "Blank form #{code} is missing from priv/judicial_forms. Run `mix dnc.setup_forms` to download it."
  end

  defp form_error_message({:unknown_form, code}) do
    "#{code} is not one of the forms this app fills."
  end

  defp form_error_message({:form_filler_failed, _status, message}) do
    "Filling the official form failed: #{message}"
  end

  defp form_error_message(reason), do: pdf_error_message(reason)

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

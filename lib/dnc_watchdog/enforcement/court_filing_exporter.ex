defmodule DncWatchdog.Enforcement.CourtFilingExporter do
  @moduledoc """
  Exports small-claims filing drafts per case as markdown and optional PDF.
  """

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.CourtFilingDraft
  alias DncWatchdog.Enforcement.LetterExporter
  alias DncWatchdog.Enforcement.LetterPdf

  def export_all(output_dir, export_opts \\ []) do
    pdf? = Keyword.get(export_opts, :pdf, false)
    File.mkdir_p!(output_dir)

    profile = Enforcement.get_claimant_profile()
    letter_opts = [claimant_profile: profile]

    Enforcement.list_cases(preload_legal_entity: true, require_violations: true)
    |> Enum.flat_map(&write_case_filing(output_dir, &1, letter_opts, pdf?))
  end

  defp write_case_filing(output_dir, case_record, letter_opts, pdf?) do
    body =
      case case_record.court_filing_draft do
        draft when draft not in [nil, ""] ->
          draft

        _ ->
          violations = Enforcement.list_violation_communications(case_record.id)
          attachments = Enforcement.list_case_attachments(case_record.id)

          if violations == [] do
            nil
          else
            CourtFilingDraft.render(case_record, violations, attachments, letter_opts)
          end
      end

    case body do
      nil ->
        []

      body ->
        attachments = Enforcement.list_case_attachments(case_record.id)
        stem = LetterExporter.safe_company_filename(case_record.company_name)
        md_path = Path.join(output_dir, "#{stem}_small_claims_filing.md")
        File.write!(md_path, body)

        if pdf? do
          pdf_path = Path.join(output_dir, "#{stem}_small_claims_filing.pdf")

          case LetterPdf.write_file(pdf_path, body, attachments) do
            {:ok, path} -> [md_path, path]
            {:error, _} -> [md_path]
          end
        else
          [md_path]
        end
    end
  end
end

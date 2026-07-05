defmodule DncWatchdog.Enforcement.CivilComplaintExporter do
  @moduledoc """
  Exports civil complaint drafts per case as markdown and optional PDF.
  """

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.CivilComplaintDraft
  alias DncWatchdog.Enforcement.FilingLimits
  alias DncWatchdog.Enforcement.LetterExporter
  alias DncWatchdog.Enforcement.LetterPdf

  def export_all(output_dir, export_opts \\ []) do
    pdf? = Keyword.get(export_opts, :pdf, false)
    File.mkdir_p!(output_dir)

    profile = Enforcement.get_claimant_profile()
    letter_opts = [claimant_profile: profile]

    Enforcement.list_cases(preload_legal_entity: true, require_violations: true)
    |> Enum.flat_map(&write_case_complaint(output_dir, &1, letter_opts, pdf?))
  end

  defp write_case_complaint(output_dir, case_record, letter_opts, pdf?) do
    body =
      case case_record.civil_complaint_draft do
        draft when draft not in [nil, ""] ->
          draft

        _ ->
          violations = Enforcement.list_violation_communications(case_record.id)

          if violations == [] do
            nil
          else
            limits = Enforcement.assess_case_filing_limits(case_record)

            CivilComplaintDraft.render(
              case_record,
              violations,
              Enforcement.list_case_attachments(case_record.id),
              Keyword.merge(letter_opts,
                filing_limits:
                  FilingLimits.civil_assess(length(violations),
                    calendar_year: limits.calendar_year,
                    high_small_claims_filings_this_year:
                      limits.small_claims_high_filings_this_year
                  )
              )
            )
          end
      end

    case body do
      nil ->
        []

      body ->
        attachments = Enforcement.list_case_attachments(case_record.id)
        stem = LetterExporter.safe_company_filename(case_record.company_name)
        md_path = Path.join(output_dir, "#{stem}_civil_complaint.md")
        File.write!(md_path, body)

        if pdf? do
          pdf_path = Path.join(output_dir, "#{stem}_civil_complaint.pdf")

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

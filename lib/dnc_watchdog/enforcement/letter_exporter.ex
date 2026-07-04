defmodule DncWatchdog.Enforcement.LetterExporter do
  @moduledoc """
  Exports demand-letter drafts per case as markdown and optional PDF.
  """

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.LetterDraft
  alias DncWatchdog.Enforcement.LetterPdf

  def export_all(output_dir, your_name, your_phone, dnc_date, export_opts \\ []) do
    pdf? = Keyword.get(export_opts, :pdf, false)
    File.mkdir_p!(output_dir)

    profile = Enforcement.get_claimant_profile()

    letter_opts = [
      claimant_profile: profile,
      claimant_name: your_name,
      claimant_phone: your_phone,
      dnc_registration_date: dnc_date
    ]

    Enforcement.list_cases(preload_legal_entity: true, require_violations: true)
    |> Enum.filter(fn case_record -> case_record.letter_draft not in [nil, ""] end)
    |> case do
      [] ->
        export_generated(output_dir, letter_opts, pdf?)

      cases ->
        cases
        |> Enum.flat_map(&write_case_letter(output_dir, &1, pdf?))
    end
  end

  @doc """
  Safe filename stem for a company/case name.
  """
  def safe_company_filename(company), do: safe_name(company)

  defp export_generated(output_dir, letter_opts, pdf?) do
    Enforcement.list_cases(preload_legal_entity: true, require_violations: true)
    |> Enum.flat_map(fn case_record ->
      violations = Enforcement.list_violation_communications(case_record.id)
      attachments = Enforcement.list_case_attachments(case_record.id)

      if violations == [] do
        []
      else
        body = LetterDraft.render(case_record, violations, attachments, letter_opts)

        write_exports(output_dir, case_record.company_name, body, attachments, pdf?)
      end
    end)
  end

  defp write_case_letter(output_dir, case_record, pdf?) do
    attachments = Enforcement.list_case_attachments(case_record.id)

    write_exports(output_dir, case_record.company_name, case_record.letter_draft, attachments, pdf?)
  end

  defp write_exports(output_dir, company_name, body, attachments, pdf?) do
    md_path = Path.join(output_dir, "#{safe_name(company_name)}_demand_letter.md")
    File.write!(md_path, body)

    if pdf? do
      pdf_path = pdf_output_path(output_dir, company_name)

      case LetterPdf.write_file(pdf_path, body, attachments) do
        {:ok, path} -> [md_path, path]
        {:error, _} -> [md_path]
      end
    else
      [md_path]
    end
  end

  defp pdf_output_path(output_dir, company_name) do
    Path.join(output_dir, "#{safe_name(company_name)}_demand_letter.pdf")
  end

  defp safe_name(company) do
    company
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> "unknown_company"
      value -> value
    end
  end
end

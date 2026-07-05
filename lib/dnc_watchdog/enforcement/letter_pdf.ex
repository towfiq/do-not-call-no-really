defmodule DncWatchdog.Enforcement.LetterPdf do
  @moduledoc """
  Renders demand letter drafts as PDF with evidence exhibits embedded.
  """

  alias DncWatchdog.Enforcement.EvidenceAttachment
  alias DncWatchdog.Enforcement.EvidenceStorage

  @styles """
  @page { size: letter; margin: 1in; }
  body { font-family: "Times New Roman", Times, serif; font-size: 12pt; line-height: 1.45; color: #000; }
  h2 { font-size: 13pt; margin: 1.5em 0 0.75em; page-break-after: avoid; }
  table { border-collapse: collapse; width: 100%; font-size: 10pt; margin-top: 0.5em; }
  th, td { border: 1px solid #999; padding: 4px 6px; vertical-align: top; text-align: left; }
  th { background: #f5f5f5; }
  .letter-body { white-space: pre-wrap; }
  .exhibit { page-break-before: always; }
  .exhibit-title { font-weight: bold; margin-bottom: 0.75em; }
  .exhibit img { display: block; max-width: 100%; max-height: 8.5in; margin: 0 auto; }
  .exhibit-note { font-style: italic; color: #444; margin-top: 0.75em; }
  """

  @doc """
  Builds printable HTML for a letter body and its attachments.
  """
  @spec build_html(String.t(), [EvidenceAttachment.t()]) :: String.t()
  def build_html(letter_body, attachments) when is_binary(letter_body) do
    {letter, appendix} = split_appendix(letter_body)

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>#{@styles}</style>
    </head>
    <body>
      <div class="letter-body">#{escape_html(letter)}</div>
      #{appendix_html(appendix)}
      #{exhibits_html(attachments)}
    </body>
    </html>
    """
  end

  @doc """
  Renders a PDF binary for the letter and embedded exhibits.

  Requires Chrome/Chromium (used by ChromicPDF).
  """
  @spec generate(String.t(), [EvidenceAttachment.t()], keyword()) ::
          {:ok, binary()} | {:error, term()}
  def generate(letter_body, attachments, opts \\ []) when is_binary(letter_body) do
    with :ok <- ensure_chromic_pdf!() do
      html = build_html(letter_body, attachments)

      case ChromicPDF.print_to_pdf({:html, html}, print_opts(opts)) do
        {:ok, base64_pdf} ->
          {:ok, Base.decode64!(base64_pdf)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Returns `:ok` when ChromicPDF is loaded and started, otherwise an error tuple.
  """
  @spec ensure_chromic_pdf!() ::
          :ok | {:error, :chromic_pdf_unavailable | :chromic_pdf_not_started}
  def ensure_chromic_pdf! do
    cond do
      not Code.ensure_loaded?(ChromicPDF) or not function_exported?(ChromicPDF, :print_to_pdf, 2) ->
        {:error, :chromic_pdf_unavailable}

      is_nil(Process.whereis(ChromicPDF)) ->
        {:error, :chromic_pdf_not_started}

      true ->
        :ok
    end
  end

  @doc """
  Writes a PDF file and returns its path.
  """
  @spec write_file(String.t(), String.t(), [EvidenceAttachment.t()], keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def write_file(output_path, letter_body, attachments, opts \\ []) do
    case generate(letter_body, attachments, opts) do
      {:ok, pdf} ->
        File.mkdir_p!(Path.dirname(output_path))
        File.write!(output_path, pdf)
        {:ok, output_path}

      error ->
        error
    end
  end

  defp print_opts(opts) do
    Keyword.merge(
      [
        print_to_pdf: %{
          "marginTop" => 1,
          "marginBottom" => 1,
          "marginLeft" => 1,
          "marginRight" => 1,
          "preferCSSPageSize" => true
        }
      ],
      opts
    )
  end

  defp split_appendix(letter_body) do
    case String.split(letter_body, "\n\nAppendix:", parts: 2) do
      [letter, appendix] -> {letter, appendix}
      [letter] -> {letter, ""}
    end
  end

  defp appendix_html(""), do: ""

  defp appendix_html(appendix) do
    {title, body} =
      case String.split(appendix, "\n", parts: 2) do
        [title, body] -> {title, body}
        [title] -> {title, ""}
      end

    """
    <h2>Appendix: #{escape_html(String.trim(title))}</h2>
    #{markdown_table_html(body)}
    """
  end

  defp markdown_table_html(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.filter(&String.starts_with?(&1, "|"))
    |> Enum.reject(&table_separator?/1)
    |> case do
      [] ->
        "<div class=\"letter-body\">#{escape_html(body)}</div>"

      rows ->
        [header | body_rows] = rows

        """
        <table>
          <thead>
            #{table_row_html(header, "th")}
          </thead>
          <tbody>
            #{Enum.map(body_rows, &table_row_html(&1, "td")) |> Enum.join("\n")}
          </tbody>
        </table>
        """
    end
  end

  defp table_separator?(line) do
    line
    |> String.replace("|", "")
    |> String.replace("-", "")
    |> String.replace(":", "")
    |> String.trim()
    |> case do
      "" -> true
      _ -> false
    end
  end

  defp table_row_html(line, tag) do
    cells =
      line
      |> String.trim("|")
      |> String.split("|")
      |> Enum.map(&String.trim/1)

    cells_html =
      cells
      |> Enum.map(fn cell -> "<#{tag}>#{escape_html(cell)}</#{tag}>" end)
      |> Enum.join()

    "<tr>#{cells_html}</tr>"
  end

  defp exhibits_html([]), do: ""

  defp exhibits_html(attachments) do
    attachments
    |> Enum.with_index(1)
    |> Enum.map(&exhibit_html/1)
    |> Enum.join("\n")
  end

  defp exhibit_html({%EvidenceAttachment{} = attachment, index}) do
    label = attachment.caption || attachment.filename
    letter = exhibit_letter(index)

    """
    <section class="exhibit">
      <div class="exhibit-title">Exhibit #{letter}: #{escape_html(label)}</div>
      #{exhibit_body_html(attachment)}
    </section>
    """
  end

  defp exhibit_body_html(%EvidenceAttachment{} = attachment) do
    cond do
      image_attachment?(attachment) ->
        case EvidenceStorage.read_file(attachment) do
          {:ok, binary} ->
            mime = attachment.content_type || mime_from_filename(attachment.filename)
            src = "data:#{mime};base64,#{Base.encode64(binary)}"
            ~s(<img src="#{src}" alt="#{escape_html(attachment.filename)}" />)

          {:error, _} ->
            ~s(<p class="exhibit-note">Could not read #{escape_html(attachment.filename)} from disk.</p>)
        end

      pdf_attachment?(attachment) ->
        ~s(<p class="exhibit-note">PDF attachment #{escape_html(attachment.filename)} is referenced in this demand package. Include the original file when mailing.</p>)

      true ->
        ~s(<p class="exhibit-note">Attachment #{escape_html(attachment.filename)} could not be rendered inline in this PDF.</p>)
    end
  end

  defp image_attachment?(%EvidenceAttachment{content_type: "image/" <> _}), do: true

  defp image_attachment?(%EvidenceAttachment{filename: filename}) do
    filename
    |> Path.extname()
    |> String.downcase()
    |> case do
      ext when ext in [".jpg", ".jpeg", ".png", ".gif", ".webp"] -> true
      _ -> false
    end
  end

  defp pdf_attachment?(%EvidenceAttachment{content_type: "application/pdf"}), do: true

  defp pdf_attachment?(%EvidenceAttachment{filename: filename}) do
    Path.extname(filename) |> String.downcase() == ".pdf"
  end

  defp mime_from_filename(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".heic" -> "image/heic"
      _ -> "application/octet-stream"
    end
  end

  defp exhibit_letter(idx) when idx <= 26, do: <<?A + idx - 1>>
  defp exhibit_letter(idx), do: "Ex#{idx}"

  defp escape_html(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end

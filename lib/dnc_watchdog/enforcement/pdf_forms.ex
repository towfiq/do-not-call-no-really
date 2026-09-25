defmodule DncWatchdog.Enforcement.PdfForms do
  @moduledoc """
  Fills blank Judicial Council of California AcroForm PDFs and concatenates parts
  into one file.

  The blank forms live in `priv/judicial_forms`; the filling itself runs through
  `priv/form_filler/fill_forms.py` in its own virtualenv, since the forms are
  encrypted XFA/AcroForm hybrids that need a real PDF library.
  """

  require Logger

  @doc """
  Renders `parts` into a single PDF binary.

  Each part is either `{:form, code, fields}` for a blank statewide form
  or `{:pdf, binary}` to append an already-rendered PDF such as the complaint.
  """
  def render(parts) when is_list(parts) do
    with :ok <- check_available(),
         {:ok, dir} <- make_temp_dir() do
      try do
        run_job(dir, parts)
      after
        File.rm_rf(dir)
      end
    end
  end

  def available? do
    check_available() == :ok
  end

  def python_path do
    Application.get_env(:dnc_watchdog, :form_filler_python) ||
      priv_path("form_filler/.venv/bin/python")
  end

  def script_path, do: priv_path("form_filler/fill_forms.py")

  def template_path(code) do
    priv_path("judicial_forms/#{template_name(code)}")
  end

  def template_available?(code), do: File.exists?(template_path(code))

  defp template_name(code) do
    code |> String.downcase() |> String.replace("-", "") |> Kernel.<>(".pdf")
  end

  defp check_available do
    cond do
      !File.exists?(python_path()) -> {:error, :form_filler_unavailable}
      !File.exists?(script_path()) -> {:error, :form_filler_script_missing}
      true -> :ok
    end
  end

  defp make_temp_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "dnc_forms_#{System.unique_integer([:positive])}_#{:os.system_time(:millisecond)}"
      )

    case File.mkdir_p(dir) do
      :ok -> {:ok, dir}
      {:error, reason} -> {:error, {:temp_dir_failed, reason}}
    end
  end

  defp run_job(dir, parts) do
    output = Path.join(dir, "packet.pdf")
    job_path = Path.join(dir, "job.json")

    with {:ok, job_parts} <- encode_parts(parts, dir),
         :ok <- File.write(job_path, Jason.encode!(%{output: output, parts: job_parts})),
         {:ok, report} <- run_filler(job_path),
         {:ok, pdf} <- File.read(output) do
      log_unmatched(report)
      {:ok, pdf}
    end
  end

  defp encode_parts(parts, dir) do
    parts
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {part, index}, {:ok, acc} ->
      case encode_part(part, dir, index) do
        {:ok, encoded} -> {:cont, {:ok, [encoded | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, encoded} -> {:ok, Enum.reverse(encoded)}
      error -> error
    end
  end

  defp encode_part({:form, code, fields}, _dir, _index) do
    if template_available?(code) do
      {:ok, %{template: template_path(code), fields: fields}}
    else
      {:error, {:template_missing, code}}
    end
  end

  defp encode_part({:pdf, binary}, dir, index) when is_binary(binary) do
    path = Path.join(dir, "part_#{index}.pdf")

    case File.write(path, binary) do
      :ok -> {:ok, %{pdf: path}}
      {:error, reason} -> {:error, {:temp_write_failed, reason}}
    end
  end

  defp run_filler(job_path) do
    case System.cmd(python_path(), [script_path(), job_path], stderr_to_stdout: false) do
      {stdout, 0} -> decode_report(stdout)
      {stdout, status} -> {:error, {:form_filler_failed, status, String.trim(stdout)}}
    end
  rescue
    error in ErlangError -> {:error, {:form_filler_failed, error.original, ""}}
  end

  defp decode_report(stdout) do
    case Jason.decode(stdout) do
      {:ok, %{"ok" => true} = report} -> {:ok, report}
      {:ok, %{"error" => message}} -> {:error, {:form_filler_failed, :error, message}}
      _ -> {:error, {:form_filler_failed, :bad_report, String.trim(stdout)}}
    end
  end

  defp log_unmatched(%{"unmatched" => [_ | _] = unmatched}) do
    Logger.warning("PDF form fields not found in template: #{Enum.join(unmatched, ", ")}")
  end

  defp log_unmatched(_), do: :ok

  defp priv_path(relative) do
    :dnc_watchdog
    |> :code.priv_dir()
    |> to_string()
    |> Path.join(relative)
  end
end

defmodule Mix.Tasks.Dnc.SetupForms do
  @shortdoc "Installs the PDF form filler and downloads blank California court forms"

  @moduledoc """
  Prepares everything needed to fill official California court forms:

      mix dnc.setup_forms

  Creates `priv/form_filler/.venv` with pypdf installed and downloads any missing
  blank Judicial Council of California forms into `priv/judicial_forms`.
  """

  use Mix.Task

  @forms %{
    "sc100.pdf" => "SC-100 Plaintiff's Claim",
    "sum100.pdf" => "SUM-100 Summons",
    "cm010.pdf" => "CM-010 Civil Case Cover Sheet",
    "pos010.pdf" => "POS-010 Proof of Service of Summons"
  }

  @sources [
    "https://courts.ca.gov/sites/default/files/courts/default/2024-11/",
    "https://courts.ca.gov/documents/"
  ]

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("Setting up the PDF form filler…")
    setup_venv()
    Enum.each(@forms, fn {file, label} -> ensure_form(file, label) end)
    Mix.shell().info("Done. Court forms are filled through priv/form_filler/.venv.")
  end

  defp setup_venv do
    venv = Path.join(filler_dir(), ".venv")
    python = Path.join(venv, "bin/python")

    unless File.exists?(python) do
      File.mkdir_p!(filler_dir())
      cmd!("python3", ["-m", "venv", venv])
    end

    cmd!(Path.join(venv, "bin/pip"), ["install", "--quiet", "--upgrade", "pypdf[crypto]"])
  end

  defp ensure_form(file, label) do
    path = Path.join(forms_dir(), file)

    if File.exists?(path) do
      Mix.shell().info("  have #{label}")
    else
      File.mkdir_p!(forms_dir())
      download(file, label, path)
    end
  end

  defp download(file, label, path) do
    Enum.find_value(@sources, fn base ->
      case cmd("curl", ["-sSL", "-m", "40", "-o", path, base <> file]) do
        {_, 0} -> valid_pdf?(path) && path
        _ -> nil
      end
    end)
    |> case do
      nil ->
        File.rm(path)
        Mix.shell().error("  could not download #{label} — get #{file} from courts.ca.gov")

      _ ->
        Mix.shell().info("  downloaded #{label}")
    end
  end

  defp valid_pdf?(path) do
    case File.read(path) do
      {:ok, <<"%PDF", _rest::binary>> = body} -> byte_size(body) > 20_000
      _ -> false
    end
  end

  defp cmd(command, args), do: System.cmd(command, args, stderr_to_stdout: true)

  defp cmd!(command, args) do
    case cmd(command, args) do
      {_output, 0} -> :ok
      {output, status} -> Mix.raise("#{command} failed (#{status}): #{output}")
    end
  end

  defp filler_dir, do: Path.join(File.cwd!(), "priv/form_filler")
  defp forms_dir, do: Path.join(File.cwd!(), "priv/judicial_forms")
end

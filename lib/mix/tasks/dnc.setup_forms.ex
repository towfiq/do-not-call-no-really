defmodule Mix.Tasks.Dnc.SetupForms do
  @shortdoc "Installs the PDF form filler and downloads blank California court forms"

  @moduledoc """
  Prepares everything needed to fill official California court forms:

      mix dnc.setup_forms

  Downloads a pinned standalone CPython into `priv/form_filler/python` (so Homebrew
  Python upgrades cannot break form filling), creates `priv/form_filler/.venv` with
  pypdf installed, and downloads any missing blank Judicial Council of California
  forms into `priv/judicial_forms`.

  On non-macOS hosts the task falls back to `python3` on PATH.
  """

  use Mix.Task

  # Pinned astral-sh/python-build-standalone release. Bump deliberately; do not
  # float to "latest" — the point is surviving host Python upgrades.
  @python_release "20251209"
  @python_version "3.12.12"

  @python_archives %{
    "arm64" => %{
      triple: "aarch64-apple-darwin",
      sha256: "c53781d2dc3bf2fd8a4dcc21843ce11f3ec5b1993442f4f78ee01bec73da0997"
    },
    "x86_64" => %{
      triple: "x86_64-apple-darwin",
      sha256: "8ca4e4634aa171f2b64a64da65f9c3faa9bbb276962f8a793f418ec7df0d6460"
    }
  }

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
    File.mkdir_p!(filler_dir())
    base = ensure_base_python()
    venv = Path.join(filler_dir(), ".venv")
    python = Path.join(venv, "bin/python")
    pin = python_pin()

    needs_venv? =
      not interpreter_runs?(python) or File.read(pin_path()) != {:ok, pin <> "\n"}

    if needs_venv? do
      File.rm_rf!(venv)
      drop_broken_launchers(venv)
      Mix.shell().info("  creating virtualenv from #{base}")
      cmd!(base, ["-m", "venv", venv])
      File.write!(pin_path(), pin <> "\n")
    end

    unless interpreter_runs?(python) do
      File.rm_rf!(venv)
      cmd!(base, ["-m", "venv", venv])
      File.write!(pin_path(), pin <> "\n")
    end

    cmd!(python, ["-m", "pip", "install", "--quiet", "--upgrade", "pypdf[crypto]"])
  end

  defp ensure_base_python do
    case :os.type() do
      {:unix, :darwin} -> ensure_standalone_python()
      _ -> system_python3()
    end
  end

  defp ensure_standalone_python do
    arch = :erlang.system_info(:system_architecture) |> to_string() |> macos_arch()
    archive = Map.fetch!(@python_archives, arch)
    pin = python_pin(arch)
    python = Path.join(standalone_dir(), "bin/python3")

    if File.read(pin_path(:standalone)) == {:ok, pin <> "\n"} and interpreter_runs?(python) do
      Mix.shell().info("  have pinned CPython #{@python_version} (#{archive.triple})")
      python
    else
      install_standalone_python(arch, archive, pin)
    end
  end

  defp install_standalone_python(arch, archive, pin) do
    File.rm_rf!(standalone_dir())
    File.mkdir_p!(filler_dir())

    url =
      "https://github.com/astral-sh/python-build-standalone/releases/download/" <>
        "#{@python_release}/cpython-#{@python_version}+#{@python_release}-#{archive.triple}-install_only.tar.gz"

    tarball = Path.join(filler_dir(), "python-standalone.tar.gz")
    Mix.shell().info("  downloading pinned CPython #{@python_version} (#{archive.triple})…")
    cmd!("curl", ["-fL", "-m", "120", "-o", tarball, url])
    verify_sha256!(tarball, archive.sha256)

    cmd!("tar", ["-xzf", tarball, "-C", filler_dir()])
    File.rm(tarball)

    python = Path.join(standalone_dir(), "bin/python3")

    unless interpreter_runs?(python) do
      Mix.raise("pinned Python at #{python} does not run after install")
    end

    File.write!(pin_path(:standalone), pin <> "\n")
    Mix.shell().info("  installed pinned CPython for #{arch}")
    python
  end

  defp system_python3 do
    case System.find_executable("python3") do
      nil -> Mix.raise("python3 is not on PATH")
      path -> path
    end
  end

  defp macos_arch(architecture) do
    cond do
      String.contains?(architecture, "arm64") or String.contains?(architecture, "aarch64") ->
        "arm64"

      String.contains?(architecture, "x86_64") ->
        "x86_64"

      true ->
        Mix.raise("unsupported macOS architecture for pinned Python: #{architecture}")
    end
  end

  defp python_pin do
    case :os.type() do
      {:unix, :darwin} ->
        arch = :erlang.system_info(:system_architecture) |> to_string() |> macos_arch()
        python_pin(arch)

      _ ->
        "system-python3"
    end
  end

  defp python_pin(arch), do: "#{@python_version}+#{@python_release}-#{arch}"

  defp verify_sha256!(path, expected) do
    {actual, 0} = System.cmd("shasum", ["-a", "256", path])
    [hash | _] = String.split(actual)

    unless String.downcase(hash) == String.downcase(expected) do
      File.rm(path)
      Mix.raise("Python tarball checksum mismatch (got #{hash}, want #{expected})")
    end
  end

  defp drop_broken_launchers(venv) do
    ~w(python python3)
    |> Enum.map(&Path.join([venv, "bin", &1]))
    |> Enum.each(fn path ->
      unless interpreter_runs?(path), do: File.rm(path)
    end)
  end

  defp interpreter_runs?(path) do
    case System.cmd(path, ["-c", "import sys"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    ErlangError -> false
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
  defp standalone_dir, do: Path.join(filler_dir(), "python")
  defp pin_path, do: Path.join(filler_dir(), ".python_pin")
  defp pin_path(:standalone), do: Path.join(filler_dir(), ".python_standalone_pin")
end

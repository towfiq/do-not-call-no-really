defmodule DncWatchdog.Enforcement.PdfFormsTest do
  use ExUnit.Case, async: true

  alias DncWatchdog.Enforcement.PdfForms

  test "select_python skips a broken unversioned symlink" do
    bin = unique_bin()

    try do
      File.mkdir_p!(bin)
      File.ln_s!("python3.14", Path.join(bin, "python"))
      File.ln_s!("python3.14", Path.join(bin, "python3"))
      current = Path.join(bin, "python3.15")
      File.write!(current, "")

      assert PdfForms.select_python(bin) == current
    after
      File.rm_rf!(bin)
    end
  end

  test "select_python prefers the unversioned launcher when it exists" do
    bin = unique_bin()

    try do
      File.mkdir_p!(bin)
      python = Path.join(bin, "python")
      File.write!(python, "")
      File.write!(Path.join(bin, "python3.15"), "")

      assert PdfForms.select_python(bin) == python
    after
      File.rm_rf!(bin)
    end
  end

  defp unique_bin do
    Path.join(System.tmp_dir!(), "dnc_py_#{System.unique_integer([:positive])}")
  end
end

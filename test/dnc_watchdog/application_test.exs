defmodule DncWatchdog.ApplicationTest do
  use ExUnit.Case, async: true

  test "launches the arm64 Chrome slice when the BEAM is running under Rosetta" do
    config = DncWatchdog.Application.chromic_pdf_config()

    if rosetta_beam?() do
      path = Keyword.fetch!(config, :chrome_executable)
      script = File.read!(path)

      assert File.regular?(path)
      assert script =~ "/usr/bin/arch -arm64"
      assert script =~ "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
      assert String.starts_with?(script, "#!/bin/sh")
    else
      refute Keyword.has_key?(config, :chrome_executable)
    end
  end

  test "chromic_pdf_config always names the ChromicPDF process" do
    config = DncWatchdog.Application.chromic_pdf_config()
    assert Keyword.fetch!(config, :name) == ChromicPDF
  end

  defp rosetta_beam? do
    match?(
      {"1\n", 0},
      System.cmd("sysctl", ["-n", "sysctl.proc_translated"], stderr_to_stdout: true)
    )
  end
end

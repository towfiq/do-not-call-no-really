defmodule Mix.Tasks.Dnc.BuildSafariHelper do
  @shortdoc "Builds the Safari helper and installs it where Safari loads it"

  @moduledoc """
  Builds the Safari app extension and installs it into `/Applications`:

      mix dnc.build_safari_helper
      mix dnc.build_safari_helper --configuration Debug
      mix dnc.build_safari_helper --no-install

  Safari loads the copy in `/Applications`, not the one Xcode leaves in its build
  directory, so a bare `xcodebuild` reports success while Safari keeps running the
  previous extension. This task builds, checks the bundle really carries the current
  `priv/chrome_extension` scripts, then replaces the installed app.

  The helper is ad-hoc signed, so Safari only loads it after Develop ->
  Allow Unsigned Extensions, which Safari forgets every time it quits.
  """

  use Mix.Task

  @app_name "DNCWatchdogUspsHelper.app"
  @bundle_id "app.dncwatchdog.usps-helper"
  @scheme "DNCWatchdogUspsHelper"
  @install_dir "/Applications"
  @build_dir "tmp/safari_build"

  @lsregister "/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [configuration: :string, install: :boolean, open: :boolean]
      )

    ensure_macos!()

    built = build(Keyword.get(opts, :configuration, "Release"))
    verify_scripts!(built)

    if Keyword.get(opts, :install, true) do
      installed = install(built)
      if Keyword.get(opts, :open, false), do: cmd!("open", [installed])
      report_next_steps()
    else
      Mix.shell().info("Built #{built} — not installed, so Safari still runs the old extension.")
    end
  end

  defp build(configuration) do
    Mix.shell().info("Building the Safari helper (#{configuration})…")

    cmd!("xcodebuild", [
      "-project",
      project_path(),
      "-scheme",
      @scheme,
      "-configuration",
      configuration,
      "-derivedDataPath",
      @build_dir,
      "build"
    ])

    app = Path.join([@build_dir, "Build/Products", configuration, @app_name])
    unless File.dir?(app), do: Mix.raise("xcodebuild succeeded but #{app} is missing.")
    app
  end

  # The extension's scripts are copied from priv/chrome_extension by the Xcode
  # project. If that phase ever stops matching, Safari and Chrome silently drift.
  defp verify_scripts!(app) do
    resources = resources_dir(app)

    unless File.exists?(Path.join(resources, "efile_fill.js")) do
      Mix.raise("efile_fill.js never made it into the bundle — check Copy Bundle Resources.")
    end

    stale =
      Path.join(resources, "*.js")
      |> Path.wildcard()
      |> Enum.filter(fn copied ->
        source = Path.join("priv/chrome_extension", Path.basename(copied))
        File.exists?(source) and File.read!(source) != File.read!(copied)
      end)
      |> Enum.map(&Path.basename/1)

    if stale != [] do
      Mix.raise("""
      The bundle carries outdated helper scripts: #{Enum.join(stale, ", ")}.
      Compare the Copy Bundle Resources phase against priv/chrome_extension.
      """)
    end
  end

  defp install(built) do
    target = Path.join(@install_dir, @app_name)
    if File.exists?(target), do: check_replaceable!(target)

    case File.rm_rf(target) do
      {:ok, _} -> :ok
      {:error, reason, _} -> Mix.raise("Cannot replace #{target} (#{reason}).")
    end

    cmd!("ditto", [built, target])
    cmd!(@lsregister, ["-f", target])
    Mix.shell().info("Installed #{version(target)} to #{target}")
    target
  end

  defp check_replaceable!(target) do
    plist = Path.join(target, "Contents/Info.plist")

    case cmd("/usr/libexec/PlistBuddy", ["-c", "Print :CFBundleIdentifier", plist]) do
      {output, 0} ->
        found = String.trim(output)

        unless found == @bundle_id do
          Mix.raise("#{target} belongs to #{found}, not #{@bundle_id} — refusing to replace it.")
        end

      _ ->
        Mix.raise("#{target} exists but has no readable Info.plist — move it aside first.")
    end
  end

  defp report_next_steps do
    if safari_running?() do
      Mix.shell().info("Safari is running with the old extension loaded — quit it (Cmd+Q) first.")
    end

    Mix.shell().info("""

    Then in Safari: Develop -> Allow Unsigned Extensions, then Settings -> Extensions
    to enable the helper, with access to california.tylertech.cloud and localhost.
    Safari forgets Allow Unsigned Extensions on every quit.
    """)
  end

  defp version(app) do
    manifest = Path.join(resources_dir(app), "manifest.json")

    with {:ok, body} <- File.read(manifest),
         [_, version] <- Regex.run(~r/"version":\s*"([^"]+)"/, body) do
      "v#{version}"
    else
      _ -> "the helper"
    end
  end

  defp ensure_macos! do
    unless :os.type() == {:unix, :darwin} do
      Mix.raise("The Safari helper only builds on macOS.")
    end

    unless System.find_executable("xcodebuild") do
      Mix.raise("xcodebuild is not on PATH — install Xcode, then run xcode-select --install.")
    end
  end

  defp safari_running?, do: match?({_, 0}, cmd("pgrep", ["-x", "Safari"]))

  defp resources_dir(app) do
    Path.join([app, "Contents/PlugIns", "#{@scheme} Extension.appex", "Contents/Resources"])
  end

  defp project_path do
    Path.join("priv/safari_extension", "#{@scheme}/#{@scheme}.xcodeproj")
  end

  defp cmd(command, args), do: System.cmd(command, args, stderr_to_stdout: true)

  defp cmd!(command, args) do
    case cmd(command, args) do
      {_output, 0} -> :ok
      {output, status} -> Mix.raise("#{command} failed (#{status}): #{output}")
    end
  end
end

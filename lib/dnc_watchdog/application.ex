defmodule DncWatchdog.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Boundary,
    top_level?: true,
    deps: [DncWatchdog, DncWatchdogWeb, Phoenix, Finch, ChromicPDF, DNSCluster, Swoosh]

  use Application

  @chrome_candidates [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium"
  ]

  @impl true
  def start(_type, _args) do
    children =
      [
        DncWatchdogWeb.Telemetry,
        DncWatchdog.Repo,
        {DNSCluster, query: Application.get_env(:dnc_watchdog, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: DncWatchdog.PubSub},
        {Finch, name: DncWatchdog.Finch},
        {ChromicPDF, chromic_pdf_config()},
        DncWatchdog.Enforcement.ContactCache,
        DncWatchdog.Enforcement.UspsBrowserHelper,
        DncWatchdogWeb.Endpoint
      ] ++ periodic_import_children() ++ periodic_tracking_refresh_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DncWatchdog.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DncWatchdogWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp periodic_import_children do
    case Application.get_env(:dnc_watchdog, :periodic_import, []) do
      config when is_list(config) ->
        if Keyword.get(config, :enabled, false) do
          [{DncWatchdog.Enforcement.PeriodicImport, config}]
        else
          []
        end

      _ ->
        []
    end
  end

  defp periodic_tracking_refresh_children do
    case Application.get_env(:dnc_watchdog, :periodic_tracking_refresh, []) do
      config when is_list(config) ->
        if Keyword.get(config, :enabled, false) do
          [{DncWatchdog.Enforcement.PeriodicTrackingRefresh, config}]
        else
          []
        end

      _ ->
        []
    end
  end

  @doc false
  @spec chromic_pdf_config() :: keyword()
  def chromic_pdf_config do
    :chromic_pdf
    |> Application.get_all_env()
    |> Keyword.put_new(:name, ChromicPDF)
    |> maybe_put_native_chrome()
  end

  # Homebrew's Elixir formula on Apple Silicon is often the x86_64 build, so the
  # BEAM runs under Rosetta. Chrome is a universal binary and then starts its
  # x86_64 slice as well. Chrome 154 refuses that combination and never emits
  # the frame-stopped event ChromicPDF waits for while opening a session, so
  # every worker dies with a 30s SpawnSession timeout. Force the arm64 slice.
  defp maybe_put_native_chrome(config) do
    case native_chrome_executable() do
      path when is_binary(path) -> Keyword.put_new(config, :chrome_executable, path)
      nil -> config
    end
  end

  defp native_chrome_executable do
    with true <- rosetta_beam?(),
         {:ok, chrome} <- find_chrome(),
         true <- arm64_slice?(chrome) do
      install_chrome_wrapper(chrome)
    else
      _ -> nil
    end
  end

  defp rosetta_beam? do
    case System.cmd("sysctl", ["-n", "sysctl.proc_translated"], stderr_to_stdout: true) do
      {"1\n", 0} -> true
      _ -> false
    end
  end

  defp find_chrome do
    case Enum.find(@chrome_candidates, &File.regular?/1) do
      nil -> :error
      path -> {:ok, path}
    end
  end

  defp arm64_slice?(path) do
    case System.cmd("lipo", ["-archs", path], stderr_to_stdout: true) do
      {out, 0} -> String.contains?(out, "arm64")
      _ -> false
    end
  end

  defp install_chrome_wrapper(chrome) do
    dir = Path.join(System.tmp_dir!(), "dnc_watchdog")
    File.mkdir_p!(dir)
    path = Path.join(dir, "chrome-arm64")

    File.write!(path, """
    #!/bin/sh
    exec /usr/bin/arch -arm64 '#{String.replace(chrome, "'", "'\\''")}' "$@"
    """)

    File.chmod!(path, 0o755)
    path
  end
end

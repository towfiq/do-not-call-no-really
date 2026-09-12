defmodule DncWatchdog.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Boundary,
    top_level?: true,
    deps: [DncWatchdog, DncWatchdogWeb, Phoenix, Finch, ChromicPDF, DNSCluster, Swoosh]

  use Application

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

  defp chromic_pdf_config do
    :chromic_pdf
    |> Application.get_all_env()
    |> Keyword.put_new(:name, ChromicPDF)
  end
end

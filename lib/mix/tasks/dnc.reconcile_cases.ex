defmodule Mix.Tasks.Dnc.ReconcileCases do
  use Mix.Task

  @shortdoc "Merge split cases for the same incoming caller/sender phone"

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")

    case DncWatchdog.Enforcement.reconcile_incoming_peer_case_assignments() do
      %{peers: peers, reassigned: reassigned} ->
        Mix.shell().info("Reconciled #{peers} peer(s); moved #{reassigned} communication(s) onto canonical cases.")
    end
  end
end

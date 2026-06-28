defmodule DncWatchdogWeb.CaseLive.Index do
  use DncWatchdogWeb, :live_view

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.Case
  alias DncWatchdog.Repo

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :cases, Enforcement.list_cases(preload_communications: true))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Case")
    |> assign(:case, Enforcement.get_case!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Case")
    |> assign(:case, %Case{status: "new", workflow_step: "intake"})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Cases")
    |> assign(:case, nil)
  end

  @impl true
  def handle_info({DncWatchdogWeb.CaseLive.FormComponent, {:saved, case}}, socket) do
    case = Repo.preload(case, :communications)
    {:noreply, stream_insert(socket, :cases, case)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case = Enforcement.get_case!(id)
    {:ok, _} = Enforcement.delete_case(case)

    {:noreply, stream_delete(socket, :cases, case)}
  end
end

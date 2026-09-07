defmodule DncWatchdogWeb.CaseLive.Index do
  use DncWatchdogWeb, :live_view

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.Case
  alias DncWatchdogWeb.FilterParams

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> stream(:cases, [], reset: true)
     |> assign(
       workflow_phase: "all",
       search_query: "",
       filtered_count: 0,
       total_count: 0
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> assign(:workflow_phase, FilterParams.parse_workflow(params))
      |> assign(:search_query, FilterParams.parse_search(params))
      |> assign_index_path()
      |> apply_action(socket.assigns.live_action, params)
      |> reload_cases()

    {:noreply, socket}
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

  defp assign_index_path(socket) do
    assign(
      socket,
      :index_path,
      FilterParams.path(
        ~p"/cases",
        socket.assigns.workflow_phase,
        socket.assigns.search_query
      )
    )
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply,
     push_patch(socket,
       to: FilterParams.path(~p"/cases", socket.assigns.workflow_phase, query)
     )}
  end

  @impl true
  def handle_event("set_workflow_filter", %{"workflow" => phase}, socket) do
    {:noreply,
     push_patch(socket,
       to: FilterParams.path(~p"/cases", phase, socket.assigns.search_query)
     )}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case = Enforcement.get_case!(id)
    {:ok, _} = Enforcement.delete_case(case)

    {:noreply, reload_cases(socket)}
  end

  @impl true
  def handle_info({DncWatchdogWeb.CaseLive.FormComponent, {:saved, _case}}, socket) do
    {:noreply, reload_cases(socket)}
  end

  defp reload_cases(socket) do
    list_opts = list_opts(socket)

    socket
    |> stream(:cases, Enforcement.list_cases(list_opts), reset: true)
    |> assign(:filtered_count, Enforcement.count_cases(list_opts))
    |> assign(:total_count, Enforcement.count_cases(total_count_opts()))
  end

  defp list_opts(socket) do
    [
      preload_communications: true,
      preload_legal_entity: true,
      require_violations: socket.assigns.search_query == "",
      workflow_phase: socket.assigns.workflow_phase,
      search: socket.assigns.search_query
    ]
  end

  defp total_count_opts do
    [require_violations: true]
  end
end

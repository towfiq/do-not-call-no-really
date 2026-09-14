defmodule DncWatchdogWeb.CaseLive.Index do
  use DncWatchdogWeb, :live_view

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.Case
  alias DncWatchdog.Enforcement.Damages
  alias DncWatchdogWeb.CommunicationCount
  alias DncWatchdogWeb.FilterParams

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> stream(:cases, [], reset: true)
     |> assign(
       workflow_phase: "all",
       search_query: "",
       min_comms: nil,
       sort_by: nil,
       sort_dir: :desc,
       filtered_count: 0,
       total_count: 0,
       damages_total: Damages.zero(),
       communications_total: 0
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> assign(:workflow_phase, FilterParams.parse_workflow(params))
      |> assign(:search_query, FilterParams.parse_search(params))
      |> FilterParams.assign_count_sort(params)
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
    assign(socket, :index_path, cases_path(socket))
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, push_patch(socket, to: cases_path(socket, search: query))}
  end

  @impl true
  def handle_event("set_workflow_filter", %{"workflow" => phase}, socket) do
    {:noreply, push_patch(socket, to: cases_path(socket, workflow: phase))}
  end

  def handle_event("set_min_comms", params, socket) do
    {:noreply,
     push_patch(socket, to: cases_path(socket, min_comms: FilterParams.parse_min_comms(params)))}
  end

  def handle_event("sort", %{"key" => key}, socket) do
    {sort_by, sort_dir} =
      FilterParams.next_sort(socket.assigns.sort_by, socket.assigns.sort_dir, key)

    {:noreply, push_patch(socket, to: cases_path(socket, sort_by: sort_by, sort_dir: sort_dir))}
  end

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

    cases =
      list_opts
      |> Enforcement.list_cases()
      |> CommunicationCount.apply_to_cases(
        socket.assigns.min_comms,
        socket.assigns.sort_by,
        socket.assigns.sort_dir
      )

    damages_total =
      cases |> Enum.map(&Damages.for_case/1) |> Enum.reduce(Damages.zero(), &Decimal.add/2)

    communications_total =
      Enum.reduce(cases, 0, fn case, acc -> acc + length(case.communications) end)

    socket
    |> stream(:cases, cases, reset: true)
    |> assign(:filtered_count, length(cases))
    |> assign(:total_count, Enforcement.count_cases(total_count_opts()))
    |> assign(:damages_total, damages_total)
    |> assign(:communications_total, communications_total)
  end

  defp cases_path(socket, overrides \\ []) do
    FilterParams.path(
      ~p"/cases",
      Keyword.get(overrides, :workflow, socket.assigns.workflow_phase),
      Keyword.get(overrides, :search, socket.assigns.search_query),
      FilterParams.count_sort_extras(socket.assigns, overrides)
    )
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

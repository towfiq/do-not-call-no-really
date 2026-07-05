defmodule DncWatchdogWeb.CommunicationLive.Index do
  use DncWatchdogWeb, :live_view

  alias DncWatchdog.Enforcement
  alias DncWatchdogWeb.FilterParams

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       violations_only: false,
       hide_excluded: true,
       hide_spam: false,
       group_by_sender: true,
       workflow_phase: "all",
       search_query: "",
       filtered_count: 0,
       total_count: 0,
       communications: [],
       communication_groups: [],
       local_sync_state: DncWatchdog.Enforcement.LocalSync.get_state(),
       local_syncing: false
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> assign(:workflow_phase, FilterParams.parse_workflow(params))
      |> assign(:search_query, FilterParams.parse_search(params))
      |> assign(
        :index_path,
        FilterParams.path(
          ~p"/communications",
          FilterParams.parse_workflow(params),
          FilterParams.parse_search(params)
        )
      )
      |> reload_communications()

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply,
     push_patch(socket,
       to: FilterParams.path(~p"/communications", socket.assigns.workflow_phase, query)
     )}
  end

  @impl true
  def handle_event("set_workflow_filter", %{"workflow" => phase}, socket) do
    {:noreply,
     push_patch(socket,
       to: FilterParams.path(~p"/communications", phase, socket.assigns.search_query)
     )}
  end

  @impl true
  def handle_event("toggle_group_by_sender", _, socket) do
    {:noreply,
     socket
     |> assign(:group_by_sender, !socket.assigns.group_by_sender)
     |> reload_communications()}
  end

  @impl true
  def handle_event("toggle_violations_only", _, socket) do
    {:noreply,
     socket
     |> assign(:violations_only, !socket.assigns.violations_only)
     |> reload_communications()}
  end

  def handle_event("toggle_hide_excluded", _, socket) do
    {:noreply,
     socket
     |> assign(:hide_excluded, !socket.assigns.hide_excluded)
     |> reload_communications()}
  end

  def handle_event("toggle_hide_spam", _, socket) do
    {:noreply,
     socket
     |> assign(:hide_spam, !socket.assigns.hide_spam)
     |> reload_communications()}
  end

  def handle_event("set_violation_status", %{"id" => id, "status" => status}, socket) do
    communication = Enforcement.get_communication!(id)

    case Enforcement.set_communication_violation_status(communication, status) do
      {:ok, _} ->
        {:noreply,
         socket
         |> reload_communications()
         |> put_flash(:info, "Updated violation status")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update violation status")}
    end
  end

  def handle_event("set_spam", %{"id" => id, "spam" => spam}, socket) do
    communication = Enforcement.get_communication!(id)
    spam? = spam in ["true", true]

    case Enforcement.set_communication_spam(communication, spam?) do
      {:ok, _} ->
        {:noreply,
         socket
         |> reload_communications()
         |> put_flash(:info, if(spam?, do: "Marked as spam", else: "Unmarked spam"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update spam status")}
    end
  end

  def handle_event("exclude_sender", %{"id" => id}, socket) do
    communication = Enforcement.get_communication!(id)
    peer = DncWatchdog.Enforcement.ContactFilter.peer_for(communication)

    case Enforcement.exclude_all_from_peer_for_communication(communication) do
      {:ok, count} ->
        {:noreply,
         socket
         |> reload_communications()
         |> put_flash(:info, "Marked #{count} communication(s) from #{peer} as not a violation; sender saved for future imports")}

      {:error, :empty_peer} ->
        {:noreply, put_flash(socket, :error, "No sender number on this row")}

      {:error, :invalid_peer} ->
        {:noreply, put_flash(socket, :error, "Could not identify sender")}
    end
  end

  def handle_event("sync_local", _, socket) do
    if socket.assigns.local_syncing do
      {:noreply, socket}
    else
      parent = self()

      {:noreply,
       socket
       |> assign(:local_syncing, true)
       |> start_async(:local_sync, fn ->
         allow_repo_sandbox(parent)
         DncWatchdog.Enforcement.LocalSync.sync()
       end)}
    end
  end

  @impl true
  def handle_async(:local_sync, {:ok, {:ok, %{summary: summary, state: state}}}, socket) do
    {:noreply,
     socket
     |> assign(:local_syncing, false)
     |> assign(:local_sync_state, state)
     |> reload_communications()
     |> put_flash(:info, DncWatchdog.Enforcement.LocalSync.summary_message(summary))}
  end

  def handle_async(:local_sync, {:ok, {:error, reason}}, socket) do
    state = DncWatchdog.Enforcement.LocalSync.get_state()

    {:noreply,
     socket
     |> assign(:local_syncing, false)
     |> assign(:local_sync_state, state)
     |> put_flash(:error, "Sync failed: #{reason}")}
  end

  def handle_async(:local_sync, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:local_syncing, false)
     |> put_flash(:error, "Sync failed: #{inspect(reason)}")}
  end

  def handle_async(:local_sync, _result, socket) do
    {:noreply,
     socket
     |> assign(:local_syncing, false)
     |> put_flash(:error, "Sync failed unexpectedly")}
  end

  defp allow_repo_sandbox(parent) do
    if sandbox_repo?() do
      Ecto.Adapters.SQL.Sandbox.allow(DncWatchdog.Repo, parent, self())
    end
  end

  defp sandbox_repo? do
    Application.get_env(:dnc_watchdog, DncWatchdog.Repo, [])
    |> Keyword.get(:pool) == Ecto.Adapters.SQL.Sandbox
  end

  defp reload_communications(socket) do
    opts = list_opts(socket)

    communications = Enforcement.list_communications(opts)
    total = Enforcement.count_communications([])

    groups =
      if socket.assigns.group_by_sender do
        DncWatchdog.Enforcement.CommunicationGroups.group_by_peer(communications)
      else
        []
      end

    socket
    |> assign(:communications, communications)
    |> assign(:communication_groups, groups)
    |> assign(:filtered_count, Enforcement.count_communications(opts))
    |> assign(:total_count, total)
  end

  defp list_opts(socket) do
    [
      violations_only: socket.assigns.violations_only,
      hide_excluded: socket.assigns.hide_excluded,
      hide_spam: socket.assigns.hide_spam,
      workflow_phase: socket.assigns.workflow_phase,
      search: socket.assigns.search_query
    ]
  end

  def group_title(%{latest: %{case: %{company_name: name}}}) when is_binary(name) and name != "" do
    name
  end

  def group_title(%{label: label}), do: label

  def last_sync_label(state), do: DncWatchdog.Enforcement.LocalSync.format_last_sync(state)
end

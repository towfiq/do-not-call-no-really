defmodule DncWatchdogWeb.CommunicationLive.Index do
  use DncWatchdogWeb, :live_view

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.Damages
  alias DncWatchdogWeb.CommunicationCount
  alias DncWatchdogWeb.FilterParams

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       violations_only: false,
       hide_excluded: true,
       hide_spam: false,
       hide_contacts: true,
       group_by_sender: true,
       workflow_phase: "all",
       search_query: "",
       min_comms: nil,
       sort_by: nil,
       sort_dir: :desc,
       filtered_count: 0,
       total_count: 0,
       communications: [],
       communication_groups: [],
       selected_peer: nil,
       selected_group: nil,
       sync_lookback_days: nil,
       sync_include_contacts: false,
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
      |> assign_optional_filters(params)
      |> FilterParams.assign_count_sort(params)
      |> assign(:selected_peer, FilterParams.parse_peer(params) || socket.assigns[:selected_peer])
      |> assign_index_path()
      |> reload_communications()

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, push_patch(socket, to: communications_path(socket, search: query))}
  end

  @impl true
  def handle_event("set_workflow_filter", %{"workflow" => phase}, socket) do
    {:noreply, push_patch(socket, to: communications_path(socket, workflow: phase))}
  end

  def handle_event("sort", %{"key" => key}, socket) do
    {sort_by, sort_dir} =
      FilterParams.next_sort(socket.assigns.sort_by, socket.assigns.sort_dir, key)

    {:noreply,
     push_patch(socket, to: communications_path(socket, sort_by: sort_by, sort_dir: sort_dir))}
  end

  @impl true
  def handle_event("apply_filters", %{"filters" => filters}, socket) do
    workflow = Map.get(filters, "workflow", socket.assigns.workflow_phase)
    min_comms = FilterParams.parse_min_comms(filters)

    socket =
      socket
      |> assign(:violations_only, FilterParams.filter_checked?(filters, "violations_only"))
      |> assign(:hide_excluded, !FilterParams.filter_checked?(filters, "include_excluded"))
      |> assign(:hide_spam, !FilterParams.filter_checked?(filters, "include_spam"))
      |> assign(:hide_contacts, !FilterParams.filter_checked?(filters, "include_contacts"))
      |> assign(:group_by_sender, FilterParams.filter_checked?(filters, "group_by_sender"))
      |> assign(:min_comms, min_comms)

    {:noreply,
     push_patch(socket,
       to: communications_path(socket, workflow: workflow, min_comms: min_comms)
     )}
  end

  def handle_event("set_violation_status", %{"id" => id, "status" => status}, socket) do
    communication = Enforcement.get_communication!(id)

    case Enforcement.set_communication_violation_status(communication, status) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> apply_violation_status_update(updated)
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
         |> put_flash(
           :info,
           "Marked #{count} communication(s) from #{peer} as not a violation; sender saved for future imports"
         )}

      {:error, :empty_peer} ->
        {:noreply, put_flash(socket, :error, "No sender number on this row")}

      {:error, :invalid_peer} ->
        {:noreply, put_flash(socket, :error, "Could not identify sender")}
    end
  end

  def handle_event("select_thread", %{"peer" => peer}, socket) do
    group = Enum.find(socket.assigns.communication_groups, &(&1.peer == peer))

    {:noreply,
     socket
     |> assign(:selected_peer, peer)
     |> assign(:selected_group, group)}
  end

  def handle_event("set_sync_options", params, socket) do
    {days, include_contacts?} = sync_options_from_params(params)

    {:noreply,
     socket
     |> assign(:sync_lookback_days, days)
     |> assign(:sync_include_contacts, include_contacts?)}
  end

  def handle_event("sync_local", params, socket) do
    if socket.assigns.local_syncing do
      {:noreply, socket}
    else
      parent = self()
      {days, include_contacts?} = sync_options_from_params(params)
      sync_opts = sync_opts(days, include_contacts?)

      {:noreply,
       socket
       |> assign(:sync_lookback_days, days)
       |> assign(:sync_include_contacts, include_contacts?)
       |> assign(:local_syncing, true)
       |> start_async(:local_sync, fn ->
         allow_repo_sandbox(parent)
         DncWatchdog.Enforcement.LocalSync.sync(sync_opts)
       end)}
    end
  end

  def handle_event("probe_call_history", params, socket) do
    phone =
      params
      |> Map.get("phone", socket.assigns.search_query)
      |> to_string()
      |> String.trim()

    phone = if phone == "", do: "4158535343", else: phone

    parent = self()

    {:noreply,
     socket
     |> assign(:local_syncing, true)
     |> start_async(:probe_call_history, fn ->
       allow_repo_sandbox(parent)
       DncWatchdog.Enforcement.Local.CallHistory.probe(phone, lookback_days: 30)
     end)}
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

  def handle_async(:probe_call_history, {:ok, {:ok, report}}, socket) do
    {:noreply,
     socket
     |> assign(:local_syncing, false)
     |> put_flash(:info, report)}
  end

  def handle_async(:probe_call_history, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:local_syncing, false)
     |> put_flash(:error, "Call History probe failed: #{reason}")}
  end

  def handle_async(:probe_call_history, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:local_syncing, false)
     |> put_flash(:error, "Call History probe failed: #{inspect(reason)}")}
  end

  defp sync_options_from_params(params) do
    days =
      case Integer.parse(to_string(Map.get(params, "lookback_days", ""))) do
        {n, _} when n > 0 -> n
        _ -> nil
      end

    {days, include_contacts_param?(params)}
  end

  defp include_contacts_param?(params) do
    case Map.get(params, "include_contacts") do
      list when is_list(list) -> Enum.any?(list, &(&1 in ["true", true]))
      value -> value in ["true", "on", true]
    end
  end

  defp sync_opts(days, include_contacts?) do
    []
    |> maybe_put_lookback(days)
    |> maybe_put_contacts(include_contacts?)
  end

  defp maybe_put_lookback(opts, days) when is_integer(days) and days > 0 do
    Keyword.put(opts, :lookback_days, days)
  end

  defp maybe_put_lookback(opts, _), do: opts

  defp maybe_put_contacts(opts, true), do: Keyword.put(opts, :skip_contacts, false)
  defp maybe_put_contacts(opts, _), do: opts

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
    opts = list_opts(socket) |> maybe_put_contact_set()
    communications = Enforcement.list_communications(opts)
    total = Enforcement.count_communications([])
    socket = present_communications(socket, communications)

    socket
    |> assign(:filtered_count, length(socket.assigns.communications))
    |> assign(:total_count, total)
  end

  defp present_communications(socket, communications) do
    grouped? = socket.assigns.group_by_sender

    communications =
      CommunicationCount.apply_to_communications(
        communications,
        socket.assigns.min_comms,
        if(grouped?, do: nil, else: socket.assigns.sort_by),
        socket.assigns.sort_dir
      )

    groups =
      if grouped? do
        communications
        |> DncWatchdog.Enforcement.CommunicationGroups.group_by_peer()
        |> CommunicationCount.apply_to_groups(
          nil,
          socket.assigns.sort_by,
          socket.assigns.sort_dir
        )
      else
        []
      end

    {selected_peer, selected_group} = select_group(socket.assigns[:selected_peer], groups)

    socket
    |> assign(:communications, communications)
    |> assign(:communication_groups, groups)
    |> assign(:selected_peer, selected_peer)
    |> assign(:selected_group, selected_group)
  end

  defp apply_violation_status_update(socket, updated) do
    if communication_visible?(updated, socket.assigns) do
      patch_communication(socket, updated)
    else
      drop_communication(socket, updated.id)
    end
  end

  defp communication_visible?(communication, assigns) do
    cond do
      assigns.violations_only and communication.violation_status != "violation" ->
        false

      assigns.hide_excluded and communication.violation_status == "excluded" ->
        false

      assigns.hide_spam and communication.spam ->
        false

      true ->
        true
    end
  end

  defp patch_communication(socket, updated) do
    communications =
      Enum.map(socket.assigns.communications, fn comm ->
        if comm.id == updated.id do
          %{updated | case: comm.case}
        else
          comm
        end
      end)

    present_communications(socket, communications)
  end

  defp drop_communication(socket, id) do
    communications = Enum.reject(socket.assigns.communications, &(&1.id == id))
    socket = present_communications(socket, communications)

    assign(socket, :filtered_count, length(socket.assigns.communications))
  end

  defp maybe_put_contact_set(opts) do
    if Keyword.get(opts, :hide_contacts, false) do
      Keyword.put(opts, :contact_set, DncWatchdog.Enforcement.ContactCache.get_set())
    else
      opts
    end
  end

  defp select_group(current_peer, groups) do
    group =
      cond do
        is_binary(current_peer) ->
          Enum.find(groups, &(&1.peer == current_peer))

        true ->
          nil
      end

    group = group || List.first(groups)

    case group do
      %{peer: peer} = g -> {peer, g}
      _ -> {nil, nil}
    end
  end

  defp assign_optional_filters(socket, params) do
    socket
    |> maybe_assign_inverted_flag(params, "include_excluded", :hide_excluded)
    |> maybe_assign_inverted_flag(params, "include_contacts", :hide_contacts)
  end

  defp maybe_assign_inverted_flag(socket, params, key, assign_key) do
    case FilterParams.parse_optional_bool(params, key) do
      nil -> socket
      value -> assign(socket, assign_key, not value)
    end
  end

  defp assign_index_path(socket) do
    assign(socket, :index_path, communications_path(socket))
  end

  defp communications_path(socket, overrides \\ []) do
    FilterParams.path(
      ~p"/communications",
      Keyword.get(overrides, :workflow, socket.assigns.workflow_phase),
      Keyword.get(overrides, :search, socket.assigns.search_query),
      FilterParams.count_sort_extras(socket.assigns, overrides)
    )
  end

  defp list_opts(socket) do
    [
      violations_only: socket.assigns.violations_only,
      hide_excluded: socket.assigns.hide_excluded and socket.assigns.search_query == "",
      hide_spam: socket.assigns.hide_spam,
      hide_contacts: socket.assigns.hide_contacts,
      workflow_phase: socket.assigns.workflow_phase,
      search: socket.assigns.search_query
    ]
  end

  def group_title(%{label: label}), do: format_peer_label(label)
  def group_title(%{peer: peer}), do: format_peer_label(peer)

  defp format_peer_label("unknown"), do: "Unknown sender"
  defp format_peer_label(peer) when is_binary(peer), do: peer
  defp format_peer_label(_), do: "Unknown sender"

  def last_sync_label(state), do: DncWatchdog.Enforcement.LocalSync.format_last_sync(state)
end

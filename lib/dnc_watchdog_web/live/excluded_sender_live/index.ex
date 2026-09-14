defmodule DncWatchdogWeb.ExcludedSenderLive.Index do
  use DncWatchdogWeb, :live_view

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.Damages
  alias DncWatchdogWeb.CommunicationCount
  alias DncWatchdogWeb.FilterParams

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Excluded senders",
       min_comms: nil,
       sort_by: nil,
       sort_dir: :desc,
       senders: [],
       excluded_counts: %{},
       damages_total: Damages.zero(),
       communications_total: 0,
       unfiltered_empty: true
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> FilterParams.assign_count_sort(params)
     |> load_senders()}
  end

  @impl true
  def handle_event("set_min_comms", params, socket) do
    {:noreply,
     push_patch(socket, to: senders_path(socket, min_comms: FilterParams.parse_min_comms(params)))}
  end

  def handle_event("sort", %{"key" => key}, socket) do
    {sort_by, sort_dir} =
      FilterParams.next_sort(socket.assigns.sort_by, socket.assigns.sort_dir, key)

    {:noreply, push_patch(socket, to: senders_path(socket, sort_by: sort_by, sort_dir: sort_dir))}
  end

  def handle_event("remove", %{"id" => id}, socket) do
    Enforcement.remove_excluded_sender!(id)

    {:noreply,
     socket
     |> load_senders()
     |> put_flash(
       :info,
       "Sender removed from excluded list. Future imports will no longer auto-exclude them."
     )}
  end

  defp load_senders(socket) do
    counts = Enforcement.excluded_message_counts_by_peer_key()
    all_senders = Enforcement.list_excluded_senders()

    senders =
      CommunicationCount.apply_to_senders(
        all_senders,
        counts,
        socket.assigns.min_comms,
        socket.assigns.sort_by,
        socket.assigns.sort_dir
      )

    communications_total =
      Enum.reduce(senders, 0, fn sender, acc -> acc + excluded_count(sender, counts) end)

    damages_total = Damages.for_count(communications_total)

    socket
    |> assign(:senders, senders)
    |> assign(:excluded_counts, counts)
    |> assign(:damages_total, damages_total)
    |> assign(:communications_total, communications_total)
    |> assign(:unfiltered_empty, all_senders == [])
  end

  defp senders_path(socket, overrides) do
    extras = FilterParams.count_sort_extras(socket.assigns, overrides)
    FilterParams.path(~p"/excluded-senders", "all", "", extras)
  end

  def excluded_count(sender, counts), do: Map.get(counts, sender.peer_key, 0)

  def excluded_damages(sender, counts) do
    Damages.format(excluded_count(sender, counts))
  end
end

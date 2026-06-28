defmodule DncWatchdogWeb.CommunicationLive.Index do
  use DncWatchdogWeb, :live_view

  alias DncWatchdog.Enforcement

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:violations_only, false)
     |> assign(:hide_excluded, true)
     |> assign(:hide_spam, false)
     |> assign(:group_by_sender, true)
     |> reload_communications()}
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

  defp reload_communications(socket) do
    opts = [
      violations_only: socket.assigns.violations_only,
      hide_excluded: socket.assigns.hide_excluded,
      hide_spam: socket.assigns.hide_spam
    ]

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

  def group_title(%{latest: %{case: %{company_name: name}}}) when is_binary(name) and name != "" do
    name
  end

  def group_title(%{label: label}), do: label
end

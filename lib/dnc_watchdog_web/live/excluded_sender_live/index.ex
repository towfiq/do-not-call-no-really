defmodule DncWatchdogWeb.ExcludedSenderLive.Index do
  use DncWatchdogWeb, :live_view

  alias DncWatchdog.Enforcement

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Excluded senders")
     |> assign(:senders, Enforcement.list_excluded_senders())}
  end

  @impl true
  def handle_event("remove", %{"id" => id}, socket) do
    Enforcement.remove_excluded_sender!(id)

    {:noreply,
     socket
     |> assign(:senders, Enforcement.list_excluded_senders())
     |> put_flash(:info, "Sender removed from excluded list. Future imports will no longer auto-exclude them.")}
  end
end

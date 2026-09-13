defmodule DncWatchdogWeb.SettingsLive.Index do
  use DncWatchdogWeb, :live_view

  alias DncWatchdog.Enforcement

  @impl true
  def mount(_params, _session, socket) do
    profile = Enforcement.get_claimant_profile()

    {:ok,
     socket
     |> assign(:page_title, "Your profile")
     |> assign(:profile, profile)
     |> assign(:chrome_extension_dir, Enforcement.chrome_extension_dir())
     |> assign(:safari_xcode_project, Enforcement.safari_xcode_project())
     |> assign_form(profile)}
  end

  @impl true
  def handle_event("validate", %{"claimant_profile" => params}, socket) do
    changeset =
      socket.assigns.profile
      |> Enforcement.change_claimant_profile(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"claimant_profile" => params}, socket) do
    case Enforcement.update_claimant_profile(params) do
      {:ok, profile} ->
        {:noreply,
         socket
         |> assign(:profile, profile)
         |> assign_form(profile)
         |> put_flash(:info, "Profile saved. Demand letters will use these defaults.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("import_from_contacts", _, socket) do
    case Enforcement.import_claimant_from_me_card() do
      {:ok, profile} ->
        {:noreply,
         socket
         |> assign(:profile, profile)
         |> assign_form(profile)
         |> put_flash(:info, "Imported your Contacts card into this profile.")}

      {:error, :not_found} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "No Me card found in Contacts. Open Contacts, edit your card, and add a home address."
         )}

      {:error, {:contacts_unreadable, _errors}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not read Contacts. Grant Full Disk Access to Terminal or Cursor, then try again."
         )}
    end
  end

  def handle_event("open_safari_xcode", _, socket) do
    path = socket.assigns.safari_xcode_project

    case System.cmd("open", [path], stderr_to_stdout: true) do
      {_output, 0} ->
        {:noreply, put_flash(socket, :info, "Opened the Safari helper in Xcode.")}

      {output, _status} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not open Xcode. Open this project yourself: #{path} (#{String.trim(output)})"
         )}
    end
  end

  defp assign_form(socket, profile) do
    assign(socket, form: to_form(Enforcement.change_claimant_profile(profile)))
  end
end

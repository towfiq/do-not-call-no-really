defmodule DncWatchdogWeb.CaseLive.Show do
  use DncWatchdogWeb, :live_view

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.EvidenceStorage

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:violations_only, false)
     |> assign(:hide_excluded, true)
     |> assign(:usps_tracking_configured, Enforcement.usps_tracking_configured?())
     |> assign(:link_case_query, "")
     |> assign(:link_case_results, [])
     |> allow_upload(:evidence,
       accept: ~w(.jpg .jpeg .png .gif .webp .heic .pdf),
       max_entries: 5,
       max_file_size: 10_000_000
     )}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply, load_case(socket, id)}
  end

  @impl true
  def handle_event("toggle_violations_only", _, socket) do
    socket =
      socket
      |> assign(:violations_only, !socket.assigns.violations_only)
      |> reload_communications()

    {:noreply, socket}
  end

  def handle_event("toggle_hide_excluded", _, socket) do
    socket =
      socket
      |> assign(:hide_excluded, !socket.assigns.hide_excluded)
      |> reload_communications()

    {:noreply, socket}
  end

  def handle_event("set_violation_status", %{"id" => id, "status" => status}, socket) do
    communication = Enforcement.get_communication!(id)

    case Enforcement.set_communication_violation_status(communication, status) do
      {:ok, _} ->
        {:noreply,
         socket
         |> reload_communications()
         |> assign(:requirements, Enforcement.workflow_requirements(socket.assigns.case))
         |> put_flash(:info, "Updated violation status")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update violation status")}
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
         |> assign(:requirements, Enforcement.workflow_requirements(socket.assigns.case))
         |> put_flash(:info, "Marked #{count} communication(s) from #{peer} as not a violation; sender saved for future imports")}

      {:error, :empty_peer} ->
        {:noreply, put_flash(socket, :error, "No sender number on this row")}

      {:error, :invalid_peer} ->
        {:noreply, put_flash(socket, :error, "Could not identify sender")}
    end
  end

  def handle_event("search_linkable_cases", params, socket) do
    query = link_case_search_query(params)
    results = Enforcement.search_linkable_cases(socket.assigns.case, query)

    {:noreply,
     socket
     |> assign(:link_case_query, query)
     |> assign(:link_case_results, results)}
  end

  def handle_event("clear_link_case_search", _, socket) do
    {:noreply, assign_link_case_search(socket, "", [])}
  end

  def handle_event("link_case", %{"id" => source_id}, socket) do
    source = Enforcement.get_case!(String.to_integer(source_id))

    case Enforcement.link_cases(socket.assigns.case, source) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_case(socket.assigns.case.id)
         |> assign_link_case_search("", [])
         |> put_flash(:info, "Linked with #{source.company_name} (case #{source.id})")}

      {:error, :same_case} ->
        {:noreply, put_flash(socket, :error, "Cannot link a case to itself")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not link cases")}
    end
  end

  def handle_event("unlink_case", %{"id" => id}, socket) do
    linked = Enforcement.get_case!(String.to_integer(id))

    case Enforcement.unlink_case(linked) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_case(socket.assigns.case.id)
         |> put_flash(:info, "Case unlinked")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not unlink case")}
    end
  end

  def handle_event("merge_case", %{"id" => id}, socket) do
    source_id = String.to_integer(id)

    case Enforcement.merge_case_into(socket.assigns.case, source_id) do
      {:ok, updated_case} ->
        {:noreply,
         socket
         |> load_case(updated_case.id)
         |> put_flash(:info, "Merged case #{source_id} into this case")}

      {:error, :same_case} ->
        {:noreply, put_flash(socket, :error, "Cannot merge a case into itself")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not merge case")}
    end
  end

  def handle_event("generate_letter", _, socket) do
    case Enforcement.generate_letter_draft(socket.assigns.case) do
      {:ok, case} ->
        {:noreply,
         socket
         |> assign(:case, case)
         |> assign(:requirements, Enforcement.workflow_requirements(case))
         |> put_flash(:info, "Letter draft generated from violations and evidence")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not generate letter draft")}
    end
  end

  def handle_event("advance_workflow", _, socket) do
    case Enforcement.advance_case_workflow(socket.assigns.case) do
      {:ok, updated_case} ->
        {:noreply,
         socket
         |> load_case(updated_case.id)
         |> put_flash(:info, "Workflow moved to #{updated_case.workflow_step}")}

      {:error, messages} when is_list(messages) ->
        {:noreply, put_flash(socket, :error, Enum.join(messages, " "))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not advance workflow")}
    end
  end

  def handle_event("validate_evidence", _params, socket), do: {:noreply, socket}

  def handle_event("upload_evidence", _params, socket) do
    case_id = socket.assigns.case.id

    uploaded =
      consume_uploaded_entries(socket, :evidence, fn %{path: path}, entry ->
        binary = File.read!(path)
        attachment =
          Enforcement.store_evidence_upload!(
            case_id,
            entry.client_name,
            binary,
            entry.client_type
          )

        {:ok, attachment}
      end)

    {:noreply,
     socket
     |> assign(:attachments, Enforcement.list_case_attachments(case_id))
     |> assign(:requirements, Enforcement.workflow_requirements(socket.assigns.case))
     |> put_flash(:info, "Uploaded #{length(uploaded)} file(s)")}
  end

  def handle_event("delete_attachment", %{"id" => id}, socket) do
    attachment = Enforcement.get_evidence_attachment!(id)
    {:ok, _} = Enforcement.delete_evidence_attachment(attachment)

    {:noreply,
     socket
     |> assign(:attachments, Enforcement.list_case_attachments(socket.assigns.case.id))
     |> assign(:requirements, Enforcement.workflow_requirements(socket.assigns.case))
     |> put_flash(:info, "Attachment removed")}
  end

  def handle_event("save_mail_tracking", %{"mail_tracking" => %{"tracking_number" => number}}, socket) do
    case Enforcement.save_mail_tracking_number(socket.assigns.case, number) do
      {:ok, updated_case} ->
        {:noreply,
         socket
         |> assign(:case, updated_case)
         |> put_flash(:info, mail_tracking_saved_message(updated_case))}

      {:error, changeset} ->
        message =
          changeset.errors
          |> Enum.map(fn {field, {msg, _}} -> "#{field} #{msg}" end)
          |> Enum.join(", ")

        {:noreply, put_flash(socket, :error, message || "Could not save tracking number")}
    end
  end

  def handle_event("refresh_mail_tracking", _, socket) do
    case Enforcement.refresh_mail_tracking(socket.assigns.case) do
      {:ok, updated_case} ->
        {:noreply,
         socket
         |> assign(:case, updated_case)
         |> put_flash(:info, "Tracking updated: #{updated_case.mail_tracking_summary}")}

      {:error, :not_configured} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "USPS API credentials not configured. Set USPS_CLIENT_ID and USPS_CLIENT_SECRET to enable automatic tracking."
         )}

      {:error, :no_tracking_number} ->
        {:noreply, put_flash(socket, :error, "Save a tracking number first")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "USPS has no record for that tracking number yet")}

      {:error, {:http_error, status}} ->
        {:noreply, put_flash(socket, :error, "USPS tracking lookup failed (HTTP #{status})")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not refresh tracking status")}
    end
  end

  @impl true
  def handle_info({DncWatchdogWeb.CaseLive.FormComponent, {:saved, case}}, socket) do
    {:noreply, load_case(socket, case.id)}
  end

  def handle_info({:case_updated, case}, socket) do
    {:noreply,
     socket
     |> assign(:case, case)
     |> assign(:requirements, Enforcement.workflow_requirements(case))}
  end

  defp load_case(socket, id) do
    case_record = Enforcement.get_case!(id)

    socket
    |> assign(:page_title, page_title(socket.assigns.live_action))
    |> assign(:case, case_record)
    |> assign(:linked_cases, Enforcement.list_linked_cases(case_record))
    |> assign_link_case_search("", [])
    |> assign(:attachments, Enforcement.list_case_attachments(case_record.id))
    |> assign(:requirements, Enforcement.workflow_requirements(case_record))
    |> reload_communications()
  end

  defp reload_communications(socket) do
    communications =
      Enforcement.list_case_communications(socket.assigns.case.id,
        violations_only: socket.assigns.violations_only,
        hide_excluded: socket.assigns.hide_excluded
      )

    assign(socket, :communications, communications)
  end

  defp assign_link_case_search(socket, query, results) do
    socket
    |> assign(:link_case_query, query)
    |> assign(:link_case_results, results)
  end

  defp link_case_search_query(params) when is_map(params) do
    params["query"] || params["value"] || ""
  end

  defp page_title(:show), do: "Show Case"
  defp page_title(:edit), do: "Edit Case"

  defp mail_tracking_saved_message(%{mail_tracking_number: nil}), do: "Tracking number cleared"

  defp mail_tracking_saved_message(%{mail_tracking_number: number}) do
    "Tracking number saved: #{number}"
  end

  def attachment_url(%{storage_path: path}), do: EvidenceStorage.public_url(path)
  def mail_tracking_url(number), do: Enforcement.mail_tracking_url(number)
end

defmodule DncWatchdogWeb.CaseLive.Show do
  use DncWatchdogWeb, :live_view

  require Logger

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.Case
  alias DncWatchdog.Enforcement.Workflow
  alias DncWatchdog.Enforcement.Damages
  alias DncWatchdog.Enforcement.EvidenceStorage
  alias DncWatchdog.Enforcement.FilingLimits
  alias DncWatchdog.Enforcement.UspsTracking
  alias DncWatchdog.Enforcement.UspsBrowserHelper
  alias DncWatchdogWeb.MailTrackingComponents

  @helper_timeout_ms :timer.seconds(120)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:violations_only, false)
     |> assign(:hide_excluded, true)
     |> assign(:hide_contacts, true)
     |> assign(:usps_tracking_configured, Enforcement.usps_tracking_configured?())
     |> assign(:usps_helper_available, false)
     |> assign(:usps_helper_timer, nil)
     |> assign(:mail_tracking_refreshing, false)
     |> assign(:mail_tracking_progress, nil)
     |> assign(:link_case_query, "")
     |> assign(:link_case_results, [])
     |> assign(:min_comms, nil)
     |> assign(:sort_by, nil)
     |> assign(:sort_dir, :desc)
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
  def handle_event("apply_filters", %{"filters" => filters}, socket) do
    {:noreply,
     socket
     |> assign(
       :violations_only,
       DncWatchdogWeb.FilterParams.filter_checked?(filters, "violations_only")
     )
     |> assign(
       :hide_excluded,
       !DncWatchdogWeb.FilterParams.filter_checked?(filters, "include_excluded")
     )
     |> assign(
       :hide_contacts,
       !DncWatchdogWeb.FilterParams.filter_checked?(filters, "include_contacts")
     )
     |> assign(:min_comms, DncWatchdogWeb.FilterParams.parse_min_comms(filters))
     |> reload_communications()}
  end

  def handle_event("sort", %{"key" => key}, socket) do
    {sort_by, sort_dir} =
      DncWatchdogWeb.FilterParams.next_sort(
        socket.assigns.sort_by,
        socket.assigns.sort_dir,
        key
      )

    {:noreply,
     socket
     |> assign(:sort_by, sort_by)
     |> assign(:sort_dir, sort_dir)
     |> reload_communications()}
  end

  def handle_event("set_violation_status", %{"id" => id, "status" => status}, socket) do
    communication = Enforcement.get_communication!(id)

    case Enforcement.set_communication_violation_status(communication, status) do
      {:ok, updated} ->
        communications =
          if communication_still_visible?(updated, socket.assigns) do
            Enum.map(socket.assigns.communications, fn comm ->
              if comm.id == updated.id, do: updated, else: comm
            end)
          else
            Enum.reject(socket.assigns.communications, &(&1.id == updated.id))
          end

        {:noreply,
         socket
         |> assign(:communications, communications)
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
         |> put_flash(
           :info,
           "Linked with #{DncWatchdog.Enforcement.Case.display_name(source)} (case #{source.id})"
         )}

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
    previous_step = socket.assigns.case.workflow_step

    case Enforcement.generate_letter_draft(socket.assigns.case) do
      {:ok, case} ->
        {:noreply,
         socket
         |> assign(:case, case)
         |> assign(:requirements, Enforcement.workflow_requirements(case))
         |> put_flash(:info, letter_draft_flash(previous_step, case, :generated))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not generate letter draft")}
    end
  end

  def handle_event("save_letter_draft", %{"letter_draft" => %{"body" => body}}, socket) do
    previous_step = socket.assigns.case.workflow_step

    case Enforcement.save_letter_draft(socket.assigns.case, body) do
      {:ok, updated_case} ->
        {:noreply,
         socket
         |> assign(:case, updated_case)
         |> assign(:requirements, Enforcement.workflow_requirements(updated_case))
         |> put_flash(:info, letter_draft_flash(previous_step, updated_case, :saved))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not save letter draft")}
    end
  end

  def handle_event("generate_court_filing", _, socket) do
    case Enforcement.generate_court_filing_draft(socket.assigns.case) do
      {:ok, case} ->
        {:noreply,
         socket
         |> load_case(case.id)
         |> put_flash(:info, "Small-claims filing draft generated")}

      {:error, :no_violations} ->
        {:noreply,
         put_flash(socket, :error, "Mark at least one violation before generating a filing draft")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not generate court filing draft")}
    end
  end

  def handle_event("generate_civil_complaint", _, socket) do
    case Enforcement.generate_civil_complaint_draft(socket.assigns.case) do
      {:ok, case} ->
        {:noreply,
         socket
         |> load_case(case.id)
         |> put_flash(:info, "Civil complaint draft generated")}

      {:error, :no_violations} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Mark at least one violation before generating a civil complaint"
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not generate civil complaint draft")}
    end
  end

  def handle_event("save_court_filing", %{"court_filing" => params}, socket) do
    attrs = court_filing_params(params)

    case Enforcement.record_court_filing(socket.assigns.case, attrs) do
      {:ok, updated_case} ->
        {:noreply,
         socket
         |> load_case(updated_case.id)
         |> put_flash(:info, "Court filing recorded")}

      {:error, changeset} ->
        message =
          changeset.errors
          |> Enum.map(fn {field, {msg, _}} -> "#{field} #{msg}" end)
          |> Enum.join(", ")

        {:noreply, put_flash(socket, :error, message || "Could not save court filing")}
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

  def handle_event("mark_settled", _, socket) do
    case Enforcement.settle_case(socket.assigns.case) do
      {:ok, updated_case} ->
        {:noreply,
         socket
         |> load_case(updated_case.id)
         |> put_flash(:info, "Case marked as settled")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not mark case as settled")}
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

  def handle_event(
        "save_mail_tracking",
        %{"mail_tracking" => %{"tracking_number" => number}},
        socket
      ) do
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
    start_browser_helper_refresh(socket)
  end

  def handle_event("refresh_mail_tracking_headless", _, socket) do
    start_headless_refresh(socket)
  end

  def handle_event("usps_helper_status", params, socket) do
    available = params["available"] in [true, "true"]
    {:noreply, assign(socket, :usps_helper_available, available)}
  end

  def handle_event("dismiss_mail_tracking_progress", _, socket) do
    {:noreply, assign(socket, :mail_tracking_progress, nil)}
  end

  @impl true
  def handle_async(:mail_tracking_refresh, {:ok, {:ok, updated_case}}, socket) do
    previous_step = socket.assigns[:mail_tracking_previous_step]

    {:noreply,
     socket
     |> assign(:mail_tracking_refreshing, false)
     |> assign(:mail_tracking_previous_step, nil)
     |> load_case(updated_case.id)
     |> finish_mail_tracking_progress(
       :ok,
       tracking_updated_message(previous_step, updated_case)
     )}
  end

  def handle_async(:mail_tracking_refresh, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:mail_tracking_refreshing, false)
     |> assign(:mail_tracking_previous_step, nil)
     |> finish_mail_tracking_progress(:error, UspsTracking.error_message(reason))}
  end

  def handle_async(:mail_tracking_refresh, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:mail_tracking_refreshing, false)
     |> assign(:mail_tracking_previous_step, nil)
     |> finish_mail_tracking_progress(
       :error,
       "Tracking lookup timed out or failed: #{inspect(reason)}. Try again or use View on USPS.com."
     )}
  end

  def handle_async(:mail_tracking_refresh, _result, socket) do
    {:noreply,
     socket
     |> assign(:mail_tracking_refreshing, false)
     |> assign(:mail_tracking_previous_step, nil)
     |> finish_mail_tracking_progress(:error, "Could not refresh tracking status")}
  end

  defp refresh_mail_tracking_safely(case_id, parent) do
    on_step = fn step -> send(parent, {:usps_tracking_step, step}) end

    case_id
    |> Enforcement.get_case!()
    |> Enforcement.refresh_mail_tracking(on_step: on_step)
  rescue
    error ->
      Logger.error(
        "[CaseLive.Show] refresh_mail_tracking failed: #{Exception.format(:error, error, __STACKTRACE__)}"
      )

      {:error, {:lookup_failed, Exception.message(error)}}
  end

  defp start_browser_helper_refresh(socket) do
    cond do
      socket.assigns[:mail_tracking_refreshing] ->
        {:noreply, socket}

      socket.assigns.case.mail_tracking_number in [nil, ""] ->
        {:noreply, put_flash(socket, :error, "Save a tracking number first")}

      true ->
        case_record = socket.assigns.case
        number = case_record.mail_tracking_number
        url = UspsTracking.tracking_url(number)

        :ok = UspsBrowserHelper.register(number, case_record.id)

        progress =
          number
          |> MailTrackingComponents.new_progress(:browser_helper)
          |> MailTrackingComponents.apply_progress_step(%{
            id: :validate,
            status: :ok,
            detail: number
          })
          |> MailTrackingComponents.apply_progress_step(%{
            id: :open_browser,
            status: :ok,
            detail: url
          })
          |> MailTrackingComponents.apply_progress_step(%{
            id: :wait_helper,
            status: :running,
            detail: helper_wait_detail(socket.assigns.usps_helper_available)
          })

        {:noreply,
         socket
         |> cancel_usps_helper_timer()
         |> assign(:mail_tracking_refreshing, true)
         |> assign(:mail_tracking_previous_step, case_record.workflow_step)
         |> assign(:mail_tracking_progress, progress)
         |> push_event("open_usps_helper", %{url: url, tracking_number: number})
         |> schedule_helper_timeout(case_record.id)}
    end
  end

  defp start_headless_refresh(socket) do
    cond do
      socket.assigns[:mail_tracking_refreshing] ->
        {:noreply, socket}

      socket.assigns.case.mail_tracking_number in [nil, ""] ->
        {:noreply, put_flash(socket, :error, "Save a tracking number first")}

      true ->
        case_id = socket.assigns.case.id
        tracking_number = socket.assigns.case.mail_tracking_number
        parent = self()
        UspsBrowserHelper.cancel(tracking_number)

        {:noreply,
         socket
         |> cancel_usps_helper_timer()
         |> assign(:mail_tracking_refreshing, true)
         |> assign(:mail_tracking_previous_step, socket.assigns.case.workflow_step)
         |> assign(
           :mail_tracking_progress,
           MailTrackingComponents.new_progress(tracking_number, :chromic)
         )
         |> start_async(:mail_tracking_refresh, fn ->
           allow_repo_sandbox(parent)
           refresh_mail_tracking_safely(case_id, parent)
         end)}
    end
  end

  defp handle_helper_result(socket, result) do
    if socket.assigns.mail_tracking_refreshing do
      do_handle_helper_result(socket, result)
    else
      socket
    end
  end

  defp do_handle_helper_result(socket, {:ok, updated_case}) do
    previous_step = socket.assigns[:mail_tracking_previous_step]

    message = tracking_updated_message(previous_step, updated_case)

    socket
    |> cancel_usps_helper_timer()
    |> assign(:mail_tracking_refreshing, false)
    |> assign(:mail_tracking_previous_step, nil)
    |> load_case(updated_case.id)
    |> apply_helper_success_progress(updated_case, message)
  end

  defp do_handle_helper_result(socket, {:error, reason}) do
    message = UspsTracking.error_message(reason)
    parse_step = if match?(%Ecto.Changeset{}, reason), do: :save, else: :parse

    socket
    |> cancel_usps_helper_timer()
    |> assign(:mail_tracking_refreshing, false)
    |> assign(:mail_tracking_previous_step, nil)
    |> then(fn socket ->
      case socket.assigns[:mail_tracking_progress] do
        nil ->
          put_flash(socket, :error, message)

        progress ->
          progress =
            progress
            |> MailTrackingComponents.apply_progress_step(%{
              id: :wait_helper,
              status: :ok,
              detail: "Received page from browser helper"
            })
            |> MailTrackingComponents.apply_progress_step(%{
              id: parse_step,
              status: :error,
              detail: message
            })
            |> MailTrackingComponents.finish_progress(:error, message)

          assign(socket, :mail_tracking_progress, progress)
      end
    end)
  end

  defp do_handle_helper_result(socket, _result), do: socket

  defp apply_helper_success_progress(socket, updated_case, message) do
    case socket.assigns[:mail_tracking_progress] do
      nil ->
        put_flash(socket, :info, message)

      progress ->
        progress =
          progress
          |> MailTrackingComponents.apply_progress_step(%{
            id: :wait_helper,
            status: :ok,
            detail: "Received page from browser helper"
          })
          |> MailTrackingComponents.apply_progress_step(%{
            id: :parse,
            status: :ok,
            detail: updated_case.mail_tracking_summary
          })
          |> MailTrackingComponents.apply_progress_step(%{
            id: :save,
            status: :ok,
            detail: updated_case.mail_tracking_summary
          })
          |> MailTrackingComponents.finish_progress(:ok, message)

        assign(socket, :mail_tracking_progress, progress)
    end
  end

  defp subscribe_mail_tracking(socket, case_id) do
    topic = UspsBrowserHelper.topic(case_id)

    cond do
      not connected?(socket) ->
        socket

      socket.assigns[:mail_tracking_topic] == topic ->
        socket

      true ->
        if old = socket.assigns[:mail_tracking_topic] do
          Phoenix.PubSub.unsubscribe(DncWatchdog.PubSub, old)
        end

        Phoenix.PubSub.subscribe(DncWatchdog.PubSub, topic)
        assign(socket, :mail_tracking_topic, topic)
    end
  end

  defp schedule_helper_timeout(socket, case_id) do
    ref = Process.send_after(self(), {:usps_helper_timeout, case_id}, @helper_timeout_ms)
    assign(socket, :usps_helper_timer, ref)
  end

  defp cancel_usps_helper_timer(socket) do
    if ref = socket.assigns[:usps_helper_timer] do
      Process.cancel_timer(ref)
    end

    assign(socket, :usps_helper_timer, nil)
  end

  defp helper_wait_detail(true) do
    "Waiting for the browser helper to read the USPS tab"
  end

  defp helper_wait_detail(_false) do
    "Waiting for the browser helper. If nothing happens, install it from Settings."
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

  defp finish_mail_tracking_progress(socket, result, message) do
    case socket.assigns[:mail_tracking_progress] do
      nil ->
        kind = if result == :ok, do: :info, else: :error
        put_flash(socket, kind, message)

      progress ->
        assign(
          socket,
          :mail_tracking_progress,
          MailTrackingComponents.finish_progress(progress, result, message)
        )
    end
  end

  @impl true
  def handle_info({:usps_tracking_step, step}, socket) do
    case socket.assigns[:mail_tracking_progress] do
      nil ->
        {:noreply, socket}

      progress ->
        {:noreply,
         assign(
           socket,
           :mail_tracking_progress,
           MailTrackingComponents.apply_progress_step(progress, step)
         )}
    end
  end

  def handle_info({:usps_helper_result, result}, socket) do
    {:noreply, handle_helper_result(socket, result)}
  end

  def handle_info({:usps_helper_timeout, case_id}, socket) do
    cond do
      socket.assigns.case.id != case_id ->
        {:noreply, socket}

      not socket.assigns.mail_tracking_refreshing ->
        {:noreply, socket}

      true ->
        number = socket.assigns.case.mail_tracking_number
        UspsBrowserHelper.cancel(number)

        {:noreply,
         socket
         |> assign(:usps_helper_timer, nil)
         |> assign(:mail_tracking_refreshing, false)
         |> assign(:mail_tracking_previous_step, nil)
         |> finish_mail_tracking_progress(:error, UspsTracking.error_message(:helper_timeout))}
    end
  end

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
    |> subscribe_mail_tracking(case_record.id)
    |> assign(:page_title, page_title(socket.assigns.live_action))
    |> assign(:case, case_record)
    |> assign_new(:mail_tracking_refreshing, fn -> false end)
    |> assign_new(:mail_tracking_progress, fn -> nil end)
    |> assign(:filing_limits, Enforcement.assess_case_filing_limits(case_record))
    |> assign(:court_filed_venues, Case.court_filed_venues())
    |> assign(:linked_cases, Enforcement.list_linked_cases(case_record))
    |> assign_link_case_search("", [])
    |> assign(:attachments, Enforcement.list_case_attachments(case_record.id))
    |> assign(:requirements, Enforcement.workflow_requirements(case_record))
    |> reload_communications()
  end

  defp reload_communications(socket) do
    opts =
      [
        violations_only: socket.assigns.violations_only,
        hide_excluded: socket.assigns.hide_excluded,
        hide_contacts: socket.assigns.hide_contacts
      ]
      |> maybe_put_contact_set()

    communications =
      socket.assigns.case.id
      |> Enforcement.list_case_communications(opts)
      |> DncWatchdogWeb.CommunicationCount.apply_to_communications(
        socket.assigns.min_comms,
        socket.assigns.sort_by,
        socket.assigns.sort_dir
      )

    assign(socket, :communications, communications)
  end

  defp maybe_put_contact_set(opts) do
    if Keyword.get(opts, :hide_contacts, false) do
      Keyword.put(opts, :contact_set, DncWatchdog.Enforcement.ContactCache.get_set())
    else
      opts
    end
  end

  defp communication_still_visible?(communication, assigns) do
    cond do
      assigns.violations_only and communication.violation_status != "violation" -> false
      assigns.hide_excluded and communication.violation_status == "excluded" -> false
      true -> true
    end
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

  defp tracking_updated_message(previous_step, updated_case) do
    if updated_case.workflow_step == "delivered" and
         Workflow.before?(previous_step, "delivered") do
      "Letter delivered — workflow moved to delivered. #{updated_case.mail_tracking_summary}"
    else
      "Tracking updated: #{updated_case.mail_tracking_summary}"
    end
  end

  defp letter_draft_flash(previous_step, case, :generated) do
    if case.workflow_step == "draft_review" and Workflow.before?(previous_step, "draft_review") do
      "Letter draft generated. Workflow moved to draft review."
    else
      "Letter draft generated from violations and evidence"
    end
  end

  defp letter_draft_flash(previous_step, case, :saved) do
    if case.workflow_step == "draft_review" and Workflow.before?(previous_step, "draft_review") do
      "Letter draft saved. Workflow moved to draft review."
    else
      "Letter draft saved"
    end
  end

  def attachment_url(%{storage_path: path}), do: EvidenceStorage.public_url(path)
  def mail_tracking_url(number), do: Enforcement.mail_tracking_url(number)

  def format_money_decimal(%Decimal{} = amount) do
    "$#{amount |> Decimal.round(2) |> Decimal.to_string(:normal)}"
  end

  def format_money_decimal(_), do: "—"

  def court_filed_venue_label(venue), do: FilingLimits.venue_label(venue)

  def court_filed_amount_value(%Case{court_filed_amount: %Decimal{} = amount}) do
    amount |> Decimal.round(2) |> Decimal.to_string(:normal)
  end

  def court_filed_amount_value(_), do: ""

  defp court_filing_params(params) do
    %{
      court_filed_at: parse_date(params["filed_at"]),
      court_filed_venue: blank_to_nil(params["venue"]),
      court_filed_amount: parse_amount(params["amount"])
    }
  end

  defp parse_date(value) when value in [nil, ""], do: nil
  defp parse_date(value), do: Date.from_iso8601!(value)

  defp parse_amount(value) when value in [nil, ""], do: nil
  defp parse_amount(value), do: Decimal.new(value)

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end

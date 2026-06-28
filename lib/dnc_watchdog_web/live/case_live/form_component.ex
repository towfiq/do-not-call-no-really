defmodule DncWatchdogWeb.CaseLive.FormComponent do
  use DncWatchdogWeb, :live_component

  alias DncWatchdog.Enforcement

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage case records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="case-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:company_name]} type="text" label="Company name" />
        <.input field={@form[:claimant_name]} type="text" label="Your name (claimant)" />
        <.input field={@form[:claimant_address]} type="textarea" label="Your mailing address" />
        <p class="-mt-2 text-xs text-zinc-500">
          Leave blank to use your saved profile from <.link navigate={~p"/settings"} class="text-brand hover:underline">Your profile</.link>.
        </p>
        <.input field={@form[:claimant_phone]} type="text" label="Your phone" />
        <.input field={@form[:claimant_email]} type="email" label="Your email" />
        <.input field={@form[:dnc_registration_date]} type="date" label="DNC registration date" />
        <.input field={@form[:stop_contact_date]} type="date" label="Date you said STOP (optional)" />
        <.input field={@form[:small_claims_county]} type="text" label="Small claims county" />
        <.input field={@form[:settlement_amount]} type="number" label="Settlement offer ($)" step="0.01" />
        <.input field={@form[:relief_amount_per_violation]} type="number" label="Relief per violation ($)" step="0.01" />
        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          options={["new", "investigating", "drafting_letter", "sent", "closed"]}
        />
        <.input
          field={@form[:workflow_step]}
          type="select"
          label="Workflow step"
          options={["intake", "triage", "evidence_review", "draft_review", "ready_to_send", "sent", "archived"]}
        />
        <.input field={@form[:notes]} type="textarea" label="Notes" />
        <.input field={@form[:letter_draft]} type="textarea" label="Letter draft" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Case</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{case: case} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(Enforcement.change_case(case))
     end)}
  end

  @impl true
  def handle_event("validate", %{"case" => case_params}, socket) do
    changeset = Enforcement.change_case(socket.assigns.case, case_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"case" => case_params}, socket) do
    save_case(socket, socket.assigns.action, case_params)
  end

  defp save_case(socket, :edit, case_params) do
    case Enforcement.update_case(socket.assigns.case, case_params) do
      {:ok, case} ->
        notify_parent({:saved, case})

        {:noreply,
         socket
         |> put_flash(:info, "Case updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_case(socket, :new, case_params) do
    case Enforcement.create_case(case_params) do
      {:ok, case} ->
        notify_parent({:saved, case})

        {:noreply,
         socket
         |> put_flash(:info, "Case created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end

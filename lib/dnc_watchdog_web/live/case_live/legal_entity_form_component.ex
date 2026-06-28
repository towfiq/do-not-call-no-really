defmodule DncWatchdogWeb.CaseLive.LegalEntityFormComponent do
  use DncWatchdogWeb, :live_component

  alias DncWatchdog.Enforcement

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 p-4">
      <h3 class="text-base font-semibold text-zinc-900">Legal entity & mailing address</h3>
      <p class="mt-1 text-sm text-zinc-600">
        Required for certified-mail demand letters.
      </p>

      <.simple_form
        for={@form}
        id="legal-entity-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="mt-4"
      >
        <div class="grid gap-4 sm:grid-cols-2">
          <.input field={@form[:legal_name]} type="text" label="Legal name" />
          <.input
            field={@form[:entity_type]}
            type="select"
            label="Entity type"
            options={[{"Company", "company"}, {"Individual", "individual"}, {"Unknown", "unknown"}]}
          />
          <.input field={@form[:street]} type="text" label="Street" />
          <.input field={@form[:city]} type="text" label="City" />
          <.input field={@form[:state]} type="text" label="State" />
          <.input field={@form[:zip]} type="text" label="ZIP" />
          <.input field={@form[:attn]} type="text" label="Attn (optional)" />
        </div>
        <.input field={@form[:notes]} type="textarea" label="Notes" />
        <:actions>
          <.button phx-disable-with="Saving...">Save legal entity</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    entity = assigns.case.legal_entity || %DncWatchdog.Enforcement.LegalEntity{}

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, to_form(Enforcement.change_legal_entity(entity), as: :legal_entity))}
  end

  @impl true
  def handle_event("validate", %{"legal_entity" => params}, socket) do
    entity = socket.assigns.case.legal_entity || %DncWatchdog.Enforcement.LegalEntity{}
    changeset = Enforcement.change_legal_entity(entity, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"legal_entity" => params}, socket) do
    case Enforcement.upsert_case_legal_entity(socket.assigns.case, params) do
      {:ok, case} ->
        send(self(), {:case_updated, case})
        {:noreply, put_flash(socket, :info, "Legal entity saved")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end

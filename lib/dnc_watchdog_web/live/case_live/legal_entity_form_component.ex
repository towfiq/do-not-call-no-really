defmodule DncWatchdogWeb.CaseLive.LegalEntityFormComponent do
  use DncWatchdogWeb, :live_component

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.SosLookup

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 p-4">
      <h3 class="text-base font-semibold text-zinc-900">Legal entity & mailing address</h3>
      <p class="mt-1 text-sm text-zinc-600">
        Required for certified-mail demand letters and SC-100 (business phone and the
        person or agent authorized to accept service).
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
          <.input field={@form[:state]} type="text" label="State / region" />
          <.input field={@form[:zip]} type="text" label="ZIP / postal code" />
          <.input field={@form[:country]} type="text" label="Country" />
          <.input field={@form[:phone]} type="text" label="Business phone" />
          <.input field={@form[:attn]} type="text" label="Attn (demand letters, optional)" />
        </div>

        <div class="mt-2 rounded-md border border-zinc-200 bg-zinc-50 p-4">
          <h4 class="text-sm font-semibold text-zinc-900">
            Person authorized to accept service
          </h4>
          <p class="mt-1 text-sm text-zinc-600">
            SC-100 item 2: if the defendant is a corporation, LLC, or public entity,
            list the registered agent (or other person authorized for service of process).
          </p>
          <div class="mt-4 grid gap-4 sm:grid-cols-2">
            <.input field={@form[:agent_name]} type="text" label="Agent name" />
            <.input field={@form[:agent_title]} type="text" label="Job title" />
            <.input field={@form[:agent_street]} type="text" label="Agent street" />
            <.input field={@form[:agent_city]} type="text" label="Agent city" />
            <.input field={@form[:agent_state]} type="text" label="Agent state" />
            <.input field={@form[:agent_zip]} type="text" label="Agent ZIP" />
            <.input field={@form[:agent_phone]} type="text" label="Agent phone (optional)" />
          </div>
        </div>

        <.input field={@form[:notes]} type="textarea" label="Notes" />
        <input
          type="hidden"
          name={@form[:sos_entity_number].name}
          value={@form[:sos_entity_number].value || ""}
        />
        <input type="hidden" name={@form[:sos_url].name} value={@form[:sos_url].value || ""} />
        <:actions>
          <.button
            type="button"
            phx-click="lookup_sos"
            phx-target={@myself}
            phx-disable-with="Looking up..."
          >
            Look up from Secretary of State
          </.button>
          <.button phx-disable-with="Saving...">Save legal entity</.button>
        </:actions>
      </.simple_form>

      <p :if={@sos_search} class="mt-3 text-sm text-zinc-600">
        Registry:
        <a href={@sos_search.url} target="_blank" rel="noreferrer" class="text-indigo-700 underline">
          {@sos_search.name}
        </a>
      </p>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    entity = assigns.case.legal_entity || %DncWatchdog.Enforcement.LegalEntity{}
    name = entity.legal_name || assigns.case.company_name
    search = SosLookup.search_page(entity.state, name, country: entity.country)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:sos_search, search)
     |> assign(:form, to_form(Enforcement.change_legal_entity(entity), as: :legal_entity))}
  end

  @impl true
  def handle_event("validate", %{"legal_entity" => params}, socket) do
    entity = socket.assigns.case.legal_entity || %DncWatchdog.Enforcement.LegalEntity{}
    changeset = Enforcement.change_legal_entity(entity, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("lookup_sos", _, socket) do
    {:ok, attrs, meta} = Enforcement.preview_legal_entity_lookup(socket.assigns.case)
    entity = socket.assigns.case.legal_entity || %DncWatchdog.Enforcement.LegalEntity{}
    changeset = Enforcement.change_legal_entity(entity, attrs)
    message = lookup_flash(meta)

    send(self(), {:lookup_flash, :info, message})

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, as: :legal_entity))
     |> assign(:sos_search, %{name: meta.registry_name, url: meta.search_url})
     |> push_event("open_sos_search", %{url: meta.search_url})}
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

  defp lookup_flash(%{found?: true, phone: phone}) when phone not in [nil, ""] do
    "Filled the registered agent from the state registry. Business phone: #{phone}. Review and save."
  end

  defp lookup_flash(%{found?: true}) do
    "Filled the registered agent from the state registry. Review and save."
  end

  defp lookup_flash(%{phone: phone, registry_name: name}) when phone not in [nil, ""] do
    "Opened #{name}. Copy the registered agent into the fields below. Business phone filled from incoming calls (#{phone})."
  end

  defp lookup_flash(%{registry_name: name}) do
    "Opened #{name}. Copy the registered agent and a business phone into the fields below, then save."
  end
end

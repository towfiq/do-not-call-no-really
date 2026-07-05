defmodule DncWatchdogWeb.CaseComponents do
  @moduledoc false
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :query, :string, default: ""
  attr :id, :string, default: "list-search"
  attr :placeholder, :string, default: "Search…"

  def list_search_form(assigns) do
    ~H"""
    <form id={@id} phx-change="search" phx-submit="search" class="mt-3 max-w-md">
      <label for={"#{@id}-input"} class="sr-only">Search</label>
      <input
        type="search"
        name="q"
        id={"#{@id}-input"}
        value={@query}
        phx-debounce="300"
        autocomplete="off"
        placeholder={@placeholder}
        class="block w-full rounded-md border-zinc-300 py-1.5 text-sm shadow-sm focus:border-brand focus:ring-brand"
      />
    </form>
    """
  end

  attr :id, :string, default: "display-filters"
  attr :violations_only, :boolean, required: true
  attr :hide_excluded, :boolean, required: true
  attr :hide_spam, :boolean, default: false
  attr :group_by_sender, :boolean, default: true
  attr :show_group_by, :boolean, default: true
  attr :show_spam, :boolean, default: true
  attr :workflow_phase, :string, default: "all"
  attr :show_workflow, :boolean, default: false

  def display_filter_form(assigns) do
    ~H"""
    <form id={@id} phx-submit="apply_filters" class="filter-panel">
      <p class="filter-panel-title">Display filters</p>
      <div class="mt-2 flex flex-wrap items-end justify-between gap-3">
        <div class="filter-grid">
          <label class="filter-checkbox">
            <input type="hidden" name="filters[violations_only]" value="false" />
            <input
              type="checkbox"
              name="filters[violations_only]"
              value="true"
              checked={@violations_only}
            /> Violations only
          </label>

          <label class="filter-checkbox">
            <input type="hidden" name="filters[include_excluded]" value="false" />
            <input
              type="checkbox"
              name="filters[include_excluded]"
              value="true"
              checked={!@hide_excluded}
            /> Include excluded
          </label>

          <label :if={@show_group_by} class="filter-checkbox">
            <input type="hidden" name="filters[group_by_sender]" value="false" />
            <input
              type="checkbox"
              name="filters[group_by_sender]"
              value="true"
              checked={@group_by_sender}
            /> Group by sender
          </label>

          <label :if={@show_spam} class="filter-checkbox">
            <input type="hidden" name="filters[include_spam]" value="false" />
            <input
              type="checkbox"
              name="filters[include_spam]"
              value="true"
              checked={!@hide_spam}
            /> Include spam
          </label>

          <label :if={@show_workflow} class="filter-checkbox">
            <span class="text-sm text-zinc-700">Workflow</span>
            <select
              name="filters[workflow]"
              class="rounded-md border-zinc-300 py-1 pl-2 pr-7 text-sm focus:border-brand focus:ring-brand"
            >
              <%= for {phase, label} <- DncWatchdog.Enforcement.Workflow.workflow_phases() do %>
                <option value={phase} selected={@workflow_phase == phase}>{label}</option>
              <% end %>
            </select>
          </label>
        </div>

        <button type="submit" class="btn-apply">Apply filters</button>
      </div>
    </form>
    """
  end

  attr :workflow_phase, :string, default: "all"
  attr :event, :string, default: "set_workflow_filter"

  def workflow_phase_filters(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-2">
      <%= for {phase, label} <- DncWatchdog.Enforcement.Workflow.workflow_phases() do %>
        <button
          type="button"
          phx-click={@event}
          phx-value-workflow={phase}
          class={[
            "rounded px-3 py-1 text-xs font-semibold ring-1",
            @workflow_phase == phase && "bg-brand/10 text-brand ring-brand/30",
            @workflow_phase != phase && "bg-white text-zinc-600 ring-zinc-300"
          ]}
        >
          {label}
        </button>
      <% end %>
    </div>
    """
  end

  attr :query, :string, default: ""
  attr :results, :list, default: []

  def link_case_typeahead(assigns) do
    assigns =
      assign(assigns, :show_results?, assigns.query != "" and assigns.results != [])

    ~H"""
    <form
      id="link-case-search"
      phx-change="search_linkable_cases"
      phx-submit={JS.push("search_linkable_cases")}
      class="relative mt-4 max-w-xl"
      phx-click-away={JS.push("clear_link_case_search")}
      autocomplete="off"
    >
      <label for="link_case_search" class="block text-sm font-medium text-zinc-700">
        Link another case
      </label>
      <input
        type="search"
        name="query"
        id="link_case_search"
        value={@query}
        phx-debounce="200"
        autocomplete="off"
        placeholder="Search by name, phone, or case #…"
        class="mt-1 block w-full rounded-lg border-zinc-300 text-sm shadow-sm focus:border-brand focus:ring-brand"
      />
      <p class="mt-1 text-xs text-zinc-500">Type to search, then click a result to link.</p>

      <ul
        :if={@show_results?}
        class="absolute z-20 mt-1 max-h-64 w-full overflow-auto rounded-lg border border-zinc-200 bg-white py-1 shadow-lg"
        role="listbox"
      >
        <%= for result <- @results do %>
          <li role="option">
            <button
              type="button"
              phx-click="link_case"
              phx-value-id={result.id}
              class="flex w-full flex-col px-3 py-2 text-left text-sm hover:bg-zinc-50"
            >
              <span class="font-medium text-zinc-900">
                {DncWatchdog.Enforcement.Case.display_name(result)}
              </span>
              <span class="text-xs text-zinc-500">Case {result.id}</span>
            </button>
          </li>
        <% end %>
      </ul>

      <p :if={@query != "" and @results == []} class="mt-2 text-sm text-zinc-500">
        No matching cases.
      </p>
    </form>
    """
  end
end

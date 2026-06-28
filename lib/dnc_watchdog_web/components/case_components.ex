defmodule DncWatchdogWeb.CaseComponents do
  @moduledoc false
  use Phoenix.Component

  alias Phoenix.LiveView.JS

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
              <span class="font-medium text-zinc-900">{result.company_name}</span>
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

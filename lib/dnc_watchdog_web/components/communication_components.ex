defmodule DncWatchdogWeb.CommunicationComponents do
  @moduledoc false
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: DncWatchdogWeb.Endpoint,
    router: DncWatchdogWeb.Router,
    statics: DncWatchdogWeb.static_paths()

  alias DncWatchdog.Enforcement.Case
  alias DncWatchdog.Enforcement.ContactFilter
  alias DncWatchdog.Enforcement.Damages
  alias DncWatchdogWeb.CommunicationCount

  attr :communication, :map, required: true
  attr :target, :any, default: nil

  def violation_button(assigns) do
    ~H"""
    <.status_button
      id={"violation-#{@communication.id}"}
      label="Violation"
      active={@communication.violation_status == "violation"}
      class="bg-rose-100 text-rose-800 ring-rose-300"
      inactive_class="bg-white text-zinc-600 ring-zinc-300 hover:bg-rose-50"
      value="violation"
      comm_id={@communication.id}
      target={@target}
    />
    """
  end

  attr :communication, :map, required: true
  attr :target, :any, default: nil

  def not_violation_button(assigns) do
    ~H"""
    <.status_button
      id={"excluded-#{@communication.id}"}
      label="Not a violation"
      active={@communication.violation_status == "excluded"}
      class="bg-zinc-200 text-zinc-800 ring-zinc-400"
      inactive_class="bg-white text-zinc-600 ring-zinc-300 hover:bg-zinc-50"
      value="excluded"
      comm_id={@communication.id}
      target={@target}
    />
    """
  end

  attr :communication, :map, required: true
  attr :target, :any, default: nil

  def spam_button(assigns) do
    spam? = assigns.communication.spam == true
    assigns = assign(assigns, :spam?, spam?)

    ~H"""
    <button
      type="button"
      id={"spam-#{@communication.id}"}
      phx-click="set_spam"
      phx-value-id={@communication.id}
      phx-value-spam={if @spam?, do: "false", else: "true"}
      phx-target={@target}
      class={[
        "rounded px-1.5 py-0.5 text-xs font-medium ring-1 whitespace-nowrap",
        @spam? && "bg-fuchsia-100 text-fuchsia-800 ring-fuchsia-300",
        !@spam? && "bg-white text-zinc-600 ring-zinc-300 hover:bg-fuchsia-50"
      ]}
    >
      {if @spam?, do: "Unspam", else: "Spam"}
    </button>
    """
  end

  attr :communication, :map, required: true
  attr :target, :any, default: nil

  def exclude_sender_button(assigns) do
    peer = ContactFilter.peer_for(assigns.communication)
    assigns = assign(assigns, :peer, peer)

    ~H"""
    <%= if @peer not in [nil, ""] do %>
      <button
        type="button"
        id={"exclude-sender-#{@communication.id}"}
        phx-click="exclude_sender"
        phx-value-id={@communication.id}
        data-confirm={exclude_sender_confirm(@peer)}
        phx-target={@target}
        class="action-chip text-zinc-700"
        title="Mark all calls and texts from this sender as not a violation"
      >
        Exclude sender
      </button>
    <% else %>
      <span class="text-xs text-zinc-400">—</span>
    <% end %>
    """
  end

  def violation_controls(assigns) do
    assigns = assign_new(assigns, :target, fn -> nil end)

    ~H"""
    <div class="flex flex-wrap gap-1">
      <.violation_button communication={@communication} target={@target} />
      <.not_violation_button communication={@communication} target={@target} />
      <.exclude_sender_button communication={@communication} target={@target} />
    </div>
    """
  end

  def exclude_sender_confirm(peer) do
    "Mark all calls and texts from #{peer} as not a violation, and auto-exclude this sender on future imports?"
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, required: true
  attr :class, :string, required: true
  attr :inactive_class, :string, required: true
  attr :value, :string, required: true
  attr :comm_id, :integer, required: true
  attr :target, :any, default: nil

  defp status_button(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      phx-click="set_violation_status"
      phx-value-id={@comm_id}
      phx-value-status={@value}
      phx-target={@target}
      class={[
        "rounded px-1.5 py-0.5 text-xs font-medium ring-1 whitespace-nowrap",
        @active && @class,
        !@active && @inactive_class
      ]}
    >
      {@label}
    </button>
    """
  end

  def violation_badge(%{status: "violation"} = assigns) do
    ~H"""
    <span class="rounded bg-rose-100 px-2 py-0.5 text-xs font-semibold text-rose-800">Violation</span>
    """
  end

  def violation_badge(%{status: "excluded"} = assigns) do
    ~H"""
    <span class="rounded bg-zinc-200 px-2 py-0.5 text-xs font-semibold text-zinc-700">Excluded</span>
    """
  end

  def violation_badge(%{status: _status, spam: true} = assigns) do
    ~H"""
    <span class="rounded bg-fuchsia-100 px-2 py-0.5 text-xs font-semibold text-fuchsia-800">
      Spam
    </span>
    """
  end

  def violation_badge(assigns) do
    ~H"""
    <span class="rounded bg-amber-100 px-2 py-0.5 text-xs font-semibold text-amber-800">Pending</span>
    """
  end

  def format_timestamp(%NaiveDateTime{} = dt) do
    dt |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_string()
  end

  def format_timestamp(value), do: to_string(value)

  def inbox_date(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%b %-d")
  end

  def inbox_date(value), do: format_timestamp(value)

  attr :groups, :list, required: true
  attr :selected_peer, :string, default: nil
  attr :group_title_fn, :any, required: true
  attr :sort_by, :string, default: nil
  attr :sort_dir, :atom, default: :desc

  def inbox_thread_list(assigns) do
    ~H"""
    <div class="inbox-list" role="listbox" aria-label="Senders">
      <div class="inbox-list-header">
        <span>Sender</span>
        <button
          type="button"
          id="sort-inbox-communications"
          phx-click="sort"
          phx-value-key="communications"
          class="table-sort-button"
          aria-sort={inbox_aria_sort(@sort_by, @sort_dir)}
        >
          Communications
          <span :if={@sort_by == "communications"} aria-hidden="true">
            {if @sort_dir == :asc, do: "↑", else: "↓"}
          </span>
        </button>
      </div>
      <%= for group <- @groups do %>
        <button
          type="button"
          id={"inbox-thread-#{group.peer}"}
          role="option"
          aria-selected={@selected_peer == group.peer}
          phx-click="select_thread"
          phx-value-peer={group.peer}
          class={["inbox-thread", @selected_peer == group.peer && "inbox-thread-active"]}
        >
          <div class="inbox-thread-main">
            <p class="inbox-thread-title">{@group_title_fn.(group)}</p>
            <p class="inbox-thread-preview">{preview_body(group.latest)}</p>
          </div>
          <div class="inbox-thread-meta">
            <p class="inbox-thread-date">{inbox_date(group.latest.timestamp)}</p>
            <span class="inbox-thread-count">{length(group.communications)}</span>
            <p class="inbox-thread-damages">{Damages.format(Damages.total(group.communications))}</p>
            <div class="mt-1 flex justify-end">
              <.violation_badge status={group.latest.violation_status} spam={group.latest.spam} />
            </div>
          </div>
        </button>
      <% end %>
    </div>
    """
  end

  attr :group, :map, required: true
  attr :group_title_fn, :any, required: true
  attr :target, :any, default: nil

  def inbox_thread_detail(assigns) do
    ~H"""
    <div class="inbox-detail">
      <div class="inbox-detail-header">
        <div class="min-w-0">
          <h2 class="text-sm font-semibold text-slate-900">{@group_title_fn.(@group)}</h2>
          <p class="text-xs text-slate-500">
            {length(@group.communications)} message{if length(@group.communications) == 1,
              do: "",
              else: "s"} · {Damages.format(Damages.total(@group.communications))} trial damages · latest {format_timestamp(
              @group.latest.timestamp
            )}
          </p>
        </div>
        <%= if @group.latest.case do %>
          <.link
            navigate={~p"/cases/#{@group.latest.case}"}
            class="text-xs font-medium text-brand hover:underline"
          >
            {Case.display_name(@group.latest.case)}
          </.link>
        <% end %>
      </div>
      <div class="inbox-detail-body" id={"communications-inbox-#{@group.peer}"}>
        <%= for comm <- @group.communications do %>
          <article id={"comm-#{comm.id}"} class="inbox-message-card">
            <div class="inbox-message-meta">
              <div class="flex flex-wrap items-center gap-2">
                <.violation_badge status={comm.violation_status} spam={comm.spam} />
                <span class="text-xs text-slate-500">
                  {format_timestamp(comm.timestamp)} · {comm.channel} · {comm.direction} · {Damages.format_row(
                    comm
                  )}
                </span>
              </div>
              <div class="flex flex-wrap gap-1">
                <.spam_button communication={comm} target={@target} />
                <.violation_button communication={comm} target={@target} />
                <.not_violation_button communication={comm} target={@target} />
                <.exclude_sender_button communication={comm} target={@target} />
              </div>
            </div>
            <p class="inbox-message-body">{full_body(comm)}</p>
            <%= if comm.case do %>
              <p class="mt-2 text-xs text-slate-500">
                Case:
                <.link
                  navigate={~p"/cases/#{comm.case}"}
                  class="font-medium text-brand hover:underline"
                >
                  {Case.display_name(comm.case)}
                </.link>
              </p>
            <% end %>
          </article>
        <% end %>
      </div>
    </div>
    """
  end

  attr :communications, :list, required: true
  attr :id_prefix, :string, required: true
  attr :class, :string, default: nil
  attr :compact, :boolean, default: false
  attr :target, :any, default: nil
  attr :sort_by, :string, default: nil
  attr :sort_dir, :atom, default: :desc
  attr :sortable, :boolean, default: true

  def communication_rows_table(assigns) do
    assigns =
      assigns
      |> assign(:damages_total, Damages.total(assigns.communications))
      |> assign(:peer_counts, CommunicationCount.peer_counts(assigns.communications))

    ~H"""
    <div class={[@class, @compact && "table-compact overflow-x-auto px-3 pb-2"]}>
      <table id={"communications-#{@id_prefix}"} class="w-full min-w-[48rem]">
        <thead>
          <tr>
            <th>When</th>
            <th aria-sort={@sortable && comms_aria_sort(@sort_by, @sort_dir)}>
              <%= if @sortable do %>
                <button
                  type="button"
                  id={"sort-#{@id_prefix}-communications"}
                  phx-click="sort"
                  phx-value-key="communications"
                  class="table-sort-button"
                >
                  Communications
                  <span :if={@sort_by == "communications"} aria-hidden="true">
                    {if @sort_dir == :asc, do: "↑", else: "↓"}
                  </span>
                </button>
              <% else %>
                Communications
              <% end %>
            </th>
            <th>Status</th>
            <th>Amount</th>
            <th>Triage</th>
            <th>Case</th>
            <th>From</th>
            <th>Type</th>
            <th>Message</th>
          </tr>
        </thead>
        <tbody>
          <%= for comm <- @communications do %>
            <tr id={"comm-#{comm.id}"}>
              <td>{format_timestamp(comm.timestamp)}</td>
              <td>{Map.get(@peer_counts, CommunicationCount.peer_key(comm), 0)}</td>
              <td><.violation_badge status={comm.violation_status} spam={comm.spam} /></td>
              <td class="whitespace-nowrap">{Damages.format_row(comm)}</td>
              <td>
                <div class="flex flex-wrap gap-1">
                  <.spam_button communication={comm} target={@target} />
                  <.violation_button communication={comm} target={@target} />
                  <.not_violation_button communication={comm} target={@target} />
                  <.exclude_sender_button communication={comm} target={@target} />
                </div>
              </td>
              <td class="max-w-[10rem] truncate">
                <%= if comm.case do %>
                  <.link
                    navigate={~p"/cases/#{comm.case}"}
                    class="text-brand hover:underline"
                    title={comm.case.company_name}
                  >
                    {Case.display_name(comm.case)}
                  </.link>
                <% else %>
                  —
                <% end %>
              </td>
              <td class="whitespace-nowrap">{comm.from_number}</td>
              <td class="whitespace-nowrap text-zinc-500">{comm.channel} · {comm.direction}</td>
              <td class="max-w-md whitespace-pre-wrap break-words text-sm">{full_body(comm)}</td>
            </tr>
          <% end %>
        </tbody>
        <tfoot>
          <tr>
            <td>Total</td>
            <td></td>
            <td></td>
            <td class="whitespace-nowrap">{Damages.format(@damages_total)}</td>
            <td></td>
            <td></td>
            <td></td>
            <td></td>
            <td></td>
          </tr>
        </tfoot>
      </table>
    </div>
    """
  end

  def preview_body(comm), do: truncate(full_body(comm), 90)

  def full_body(%{channel: "sms", body: body}) when is_binary(body) and body != "" do
    String.trim(body)
  end

  def full_body(%{channel: "call", duration_seconds: seconds}) do
    "Call (#{seconds}s)"
  end

  def full_body(_), do: "—"

  defp truncate(text, max) do
    if String.length(text) > max, do: String.slice(text, 0, max - 3) <> "...", else: text
  end

  defp inbox_aria_sort("communications", :asc), do: "ascending"
  defp inbox_aria_sort("communications", _dir), do: "descending"
  defp inbox_aria_sort(_sort_by, _dir), do: "none"

  defp comms_aria_sort(sort_by, sort_dir), do: inbox_aria_sort(sort_by, sort_dir)
end

defmodule DncWatchdogWeb.CommunicationComponents do
  @moduledoc false
  use Phoenix.Component

  import DncWatchdogWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: DncWatchdogWeb.Endpoint,
    router: DncWatchdogWeb.Router,
    statics: DncWatchdogWeb.static_paths()

  alias DncWatchdog.Enforcement.ContactFilter

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
        "rounded px-2 py-1 text-xs font-semibold ring-1 whitespace-nowrap",
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
        class="rounded px-2 py-1 text-xs font-semibold text-zinc-700 ring-1 ring-zinc-300 hover:bg-zinc-100"
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
        "rounded px-2 py-1 text-xs font-semibold ring-1 whitespace-nowrap",
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
    <span class="rounded bg-fuchsia-100 px-2 py-0.5 text-xs font-semibold text-fuchsia-800">Spam</span>
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

  attr :communications, :list, required: true
  attr :id_prefix, :string, required: true
  attr :class, :string, default: nil

  def communication_rows_table(assigns) do
    ~H"""
    <div class={@class}>
      <.table
        id={"communications-#{@id_prefix}"}
        rows={@communications}
        row_id={&("comm-#{&1.id}")}
      >
      <:col :let={comm} label="Date & time">{format_timestamp(comm.timestamp)}</:col>
      <:col :let={comm} label="Status">
        <.violation_badge status={comm.violation_status} spam={comm.spam} />
      </:col>
      <:col :let={comm} label="Spam">
        <.spam_button communication={comm} />
      </:col>
      <:col :let={comm} label="Violation">
        <.violation_button communication={comm} />
      </:col>
      <:col :let={comm} label="Not a violation">
        <.not_violation_button communication={comm} />
      </:col>
      <:col :let={comm} label="Sender">
        <.exclude_sender_button communication={comm} />
      </:col>
      <:col :let={comm} label="Case">
        <%= if comm.case do %>
          <.link navigate={~p"/cases/#{comm.case}"} class="text-brand hover:underline">
            {comm.case.company_name}
          </.link>
        <% else %>
          —
        <% end %>
      </:col>
      <:col :let={comm} label="Channel">{comm.channel}</:col>
      <:col :let={comm} label="Dir">{comm.direction}</:col>
      <:col :let={comm} label="From">{comm.from_number}</:col>
      <:col :let={comm} label="To">{comm.to_number}</:col>
      <:col :let={comm} label="Message">{preview_body(comm)}</:col>
      </.table>
    </div>
    """
  end

  def preview_body(%{channel: "sms", body: body}) when is_binary(body) and body != "" do
    truncate(body)
  end

  def preview_body(%{channel: "call", duration_seconds: seconds}) do
    "Call (#{seconds}s)"
  end

  def preview_body(_), do: "—"

  defp truncate(text) do
    if String.length(text) > 120, do: String.slice(text, 0, 117) <> "...", else: text
  end
end

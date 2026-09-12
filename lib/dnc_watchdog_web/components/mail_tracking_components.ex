defmodule DncWatchdogWeb.MailTrackingComponents do
  @moduledoc false

  use Phoenix.Component

  import DncWatchdogWeb.CoreComponents, only: [button: 1, icon: 1]

  alias DncWatchdog.Enforcement.UspsTracking

  def new_progress(tracking_number, mode \\ :browser_helper) do
    %{
      tracking_number: tracking_number,
      tracking_url: UspsTracking.tracking_url(tracking_number),
      mode: mode,
      running: true,
      result: nil,
      error: nil,
      summary: nil,
      steps: UspsTracking.progress_steps(mode)
    }
  end

  def apply_progress_step(progress, step) when is_map(step) do
    id = Map.fetch!(step, :id)
    status = Map.fetch!(step, :status)

    steps =
      Enum.map(progress.steps, fn existing ->
        if existing.id == id do
          detail =
            if Map.has_key?(step, :detail), do: step.detail, else: existing.detail

          %{existing | status: status, detail: detail}
        else
          existing
        end
      end)

    %{progress | steps: steps}
  end

  def finish_progress(progress, :ok, message) do
    %{
      progress
      | running: false,
        result: :ok,
        summary: message,
        error: nil,
        steps: skip_pending_steps(progress.steps)
    }
  end

  def finish_progress(progress, :error, message) do
    steps =
      Enum.map(progress.steps, fn
        %{status: :running} = step ->
          %{step | status: :error, detail: step.detail || message}

        %{status: :pending} = step ->
          %{step | status: :skipped, detail: "Skipped because an earlier step failed"}

        step ->
          step
      end)

    %{progress | running: false, result: :error, error: message, steps: steps}
  end

  defp skip_pending_steps(steps) do
    Enum.map(steps, fn
      %{status: :pending} = step -> %{step | status: :skipped}
      step -> step
    end)
  end

  attr :status, :string, required: true

  def mail_delivery_badge(assigns) do
    ~H"""
    <span class={[
      "badge",
      @status == "delivered" && "badge-success",
      @status == "returned" && "bg-rose-50 text-rose-700 ring-rose-600/20",
      @status == "out_for_delivery" && "bg-sky-50 text-sky-700 ring-sky-600/20",
      @status == "in_transit" && "bg-blue-50 text-blue-700 ring-blue-600/20",
      @status == "pre_shipment" && "badge-neutral",
      @status == "alert" && "badge-warning",
      @status in ["pending", "unknown"] && "badge-neutral"
    ]}>
      {mail_delivery_label(@status)}
    </span>
    """
  end

  def mail_delivery_label("delivered"), do: "Delivered"
  def mail_delivery_label("returned"), do: "Returned / rejected"
  def mail_delivery_label("out_for_delivery"), do: "Out for delivery"
  def mail_delivery_label("in_transit"), do: "In transit"
  def mail_delivery_label("pre_shipment"), do: "Pre-shipment"
  def mail_delivery_label("alert"), do: "Delivery alert"
  def mail_delivery_label("pending"), do: "Not checked yet"
  def mail_delivery_label("unknown"), do: "Unknown"
  def mail_delivery_label(status), do: status

  def format_checked_at(nil), do: "Never"

  def format_checked_at(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  end

  attr :progress, :map, required: true

  def mail_tracking_progress_dialog(assigns) do
    ~H"""
    <div
      id="mail-tracking-progress"
      class="mt-4 rounded-xl border border-indigo-200 bg-white p-4 shadow-sm ring-1 ring-indigo-100"
      role="status"
      aria-live="polite"
      aria-labelledby="mail-tracking-progress-title"
    >
      <h4 id="mail-tracking-progress-title" class="text-sm font-semibold text-zinc-900">
        {progress_heading(@progress)}
      </h4>
      <p class="mt-1 text-sm text-zinc-600">
        Tracking number <span class="font-mono">{@progress.tracking_number}</span>
      </p>
      <p
        :if={helper_waiting?(@progress)}
        class="mt-2 text-sm text-zinc-600"
        id="mail-tracking-helper-hint"
      >
        Keep the USPS tab open. The Chrome helper sends status back once the page finishes loading.
        Install the helper from Settings if this is your first time.
      </p>

      <ol class="mt-4 space-y-3" id="mail-tracking-progress-steps">
        <li :for={step <- @progress.steps} class="flex gap-3" id={"mail-tracking-step-#{step.id}"}>
          <span class="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center">
            <.icon
              :if={step.status == :running}
              name="hero-arrow-path"
              class="h-5 w-5 animate-spin text-indigo-600"
            />
            <.icon
              :if={step.status == :ok}
              name="hero-check-circle-mini"
              class="h-5 w-5 text-emerald-600"
            />
            <.icon
              :if={step.status == :error}
              name="hero-exclamation-circle-mini"
              class="h-5 w-5 text-rose-600"
            />
            <span :if={step.status == :pending} class="h-2.5 w-2.5 rounded-full bg-zinc-300" />
            <span :if={step.status == :skipped} class="h-2.5 w-2.5 rounded-full bg-zinc-200" />
          </span>
          <div class="min-w-0 flex-1">
            <p class={[
              "text-sm font-medium",
              step.status == :error && "text-rose-800",
              step.status == :skipped && "text-zinc-400",
              step.status not in [:error, :skipped] && "text-zinc-800"
            ]}>
              {step.label}
            </p>
            <p
              :if={step.detail}
              class={[
                "mt-0.5 text-sm break-words",
                step.status == :error && "text-rose-700",
                step.status == :skipped && "text-zinc-400",
                step.status not in [:error, :skipped] && "text-zinc-600"
              ]}
            >
              {step.detail}
            </p>
          </div>
        </li>
      </ol>

      <div
        :if={@progress.error}
        id="mail-tracking-progress-error"
        class="mt-4 rounded-lg bg-rose-50 p-3 text-sm text-rose-900"
      >
        {@progress.error}
      </div>

      <div
        :if={@progress.result == :ok && @progress.summary}
        id="mail-tracking-progress-success"
        class="mt-4 rounded-lg bg-emerald-50 p-3 text-sm text-emerald-900"
      >
        {@progress.summary}
      </div>

      <div :if={not @progress.running} class="mt-4 flex flex-wrap items-center gap-3">
        <.button type="button" phx-click="dismiss_mail_tracking_progress">Close</.button>
        <.button
          :if={@progress.result == :error && @progress.mode == :browser_helper}
          id="refresh-mail-tracking-headless-button"
          type="button"
          phx-click="refresh_mail_tracking_headless"
        >
          Try headless Chrome
        </.button>
        <.link
          :if={@progress.result == :error && @progress.mode == :browser_helper}
          navigate="/settings"
          class="text-sm font-semibold text-zinc-700 hover:text-zinc-900"
        >
          Helper install instructions
        </.link>
        <.link
          :if={@progress.tracking_url}
          href={@progress.tracking_url}
          target="_blank"
          rel="noopener noreferrer"
          class="text-sm font-semibold text-zinc-700 hover:text-zinc-900"
        >
          View on USPS.com
        </.link>
      </div>
    </div>
    """
  end

  defp progress_heading(%{running: true} = progress) do
    if helper_waiting?(progress), do: "Waiting for Chrome helper", else: "Checking USPS tracking"
  end

  defp progress_heading(%{result: :ok}), do: "Tracking updated"
  defp progress_heading(_), do: "Tracking check failed"

  defp helper_waiting?(progress) do
    progress.mode == :browser_helper and
      Enum.any?(progress.steps, &(&1.id == :wait_helper and &1.status == :running))
  end
end

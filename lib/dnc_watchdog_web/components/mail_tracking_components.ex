defmodule DncWatchdogWeb.MailTrackingComponents do
  @moduledoc false

  use Phoenix.Component

  attr :status, :string, required: true

  def mail_delivery_badge(assigns) do
    ~H"""
    <span class={[
      "rounded px-2 py-0.5 text-xs font-semibold",
      @status == "delivered" && "bg-emerald-100 text-emerald-800",
      @status == "returned" && "bg-rose-100 text-rose-800",
      @status == "out_for_delivery" && "bg-sky-100 text-sky-800",
      @status == "in_transit" && "bg-blue-100 text-blue-800",
      @status == "pre_shipment" && "bg-zinc-200 text-zinc-700",
      @status == "alert" && "bg-amber-100 text-amber-800",
      @status == "pending" && "bg-zinc-100 text-zinc-600",
      @status == "unknown" && "bg-zinc-100 text-zinc-600"
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
end

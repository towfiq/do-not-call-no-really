defmodule DncWatchdogWeb.MailTrackingComponents do
  @moduledoc false

  use Phoenix.Component

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
end

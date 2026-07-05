defmodule DncWatchdogWeb.Nav do
  @moduledoc false

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: DncWatchdogWeb.Endpoint,
    router: DncWatchdogWeb.Router,
    statics: DncWatchdogWeb.static_paths()

  import DncWatchdogWeb.CoreComponents, only: [icon: 1]

  def on_mount(:assign_current_path, _params, _session, socket) do
    path =
      case Phoenix.LiveView.get_connect_info(socket, :uri) do
        %URI{path: path} when is_binary(path) -> path
        _ -> "/"
      end

    {:cont, assign(socket, :current_path, path)}
  end

  def nav_active?(current_path, target) when is_binary(current_path) and is_binary(target) do
    cond do
      target == "/" -> current_path == "/"
      true -> String.starts_with?(current_path, target)
    end
  end

  def nav_active?(_, _), do: false

  attr :navigate, :string, required: true
  attr :current_path, :string, default: "/"
  attr :icon, :string, required: true
  slot :inner_block, required: true

  def sidebar_link(assigns) do
    assigns = assign(assigns, :active, nav_active?(assigns.current_path, assigns.navigate))

    ~H"""
    <.link navigate={@navigate} class={["sidebar-link", @active && "sidebar-link-active"]}>
      <.icon name={@icon} class="h-5 w-5 shrink-0 opacity-80" />
      <span>{render_slot(@inner_block)}</span>
    </.link>
    """
  end
end

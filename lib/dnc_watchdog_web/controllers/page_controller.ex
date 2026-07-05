defmodule DncWatchdogWeb.PageController do
  use DncWatchdogWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

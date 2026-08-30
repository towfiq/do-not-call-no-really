defmodule DncWatchdog.Enforcement.ContactCache do
  @moduledoc """
  Caches macOS Contacts phone/email sets so list and count queries do not
  re-read Address Book on every LiveView event.
  """

  use GenServer

  alias DncWatchdog.Enforcement.ContactFilter
  alias DncWatchdog.Enforcement.Local.Contacts

  @refresh_ms :timer.minutes(5)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the cached contact set (`%{phones: ..., emails: ...}`).
  """
  def get_set do
    GenServer.call(__MODULE__, :get_set)
  end

  @doc """
  Reloads contacts from disk immediately.
  """
  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  @impl true
  def init(_opts) do
    schedule_refresh()
    {:ok, load_state()}
  end

  @impl true
  def handle_call(:get_set, _from, state), do: {:reply, state.set, state}

  @impl true
  def handle_cast(:refresh, _state), do: {:noreply, load_state()}

  @impl true
  def handle_info(:refresh, _state) do
    schedule_refresh()
    {:noreply, load_state()}
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_ms)
  end

  defp load_state do
    case Contacts.load() do
      {:ok, set, _paths} -> %{set: set}
      {:error, _} -> %{set: ContactFilter.empty_set()}
    end
  end
end

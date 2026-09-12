defmodule DncWatchdog.Enforcement.UspsBrowserHelper do
  @moduledoc """
  Holds in-flight interactive tracking lookups so the Chrome helper can
  POST a real USPS page back to this local app.
  """

  use GenServer

  @ttl_ms :timer.minutes(3)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Directory containing the unpacked Chrome extension.
  """
  def extension_dir do
    src = Path.expand("priv/chrome_extension")

    if File.dir?(src) do
      src
    else
      Path.join(:code.priv_dir(:dnc_watchdog), "chrome_extension")
    end
  end

  def topic(case_id), do: "mail_tracking:#{case_id}"

  def register(tracking_number, case_id, opts \\ [])
      when is_binary(tracking_number) and is_integer(case_id) do
    GenServer.call(__MODULE__, {:register, tracking_number, case_id, opts})
  end

  def take(tracking_number) do
    GenServer.call(__MODULE__, {:take, tracking_number})
  end

  def cancel(tracking_number) do
    GenServer.call(__MODULE__, {:cancel, tracking_number})
  end

  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(_opts) do
    {:ok, %{lookups: %{}}}
  end

  @impl true
  def handle_call({:register, tracking_number, case_id, opts}, _from, state) do
    ttl = Keyword.get(opts, :ttl_ms, @ttl_ms)
    now = now_ms()
    lookups = drop_expired(state.lookups, now)

    pending = %{
      case_id: case_id,
      expires_at: now + ttl
    }

    {:reply, :ok, %{state | lookups: Map.put(lookups, tracking_number, pending)}}
  end

  def handle_call({:take, tracking_number}, _from, state) do
    now = now_ms()
    lookups = drop_expired(state.lookups, now)

    case Map.pop(lookups, tracking_number) do
      {nil, lookups} ->
        {:reply, {:error, :not_pending}, %{state | lookups: lookups}}

      {pending, lookups} ->
        {:reply, {:ok, pending}, %{state | lookups: lookups}}
    end
  end

  def handle_call({:cancel, tracking_number}, _from, state) do
    lookups = Map.delete(state.lookups, tracking_number)
    {:reply, :ok, %{state | lookups: lookups}}
  end

  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %{lookups: %{}}}
  end

  defp drop_expired(lookups, now) do
    Map.reject(lookups, fn {_number, pending} -> pending.expires_at <= now end)
  end

  defp now_ms, do: System.system_time(:millisecond)
end

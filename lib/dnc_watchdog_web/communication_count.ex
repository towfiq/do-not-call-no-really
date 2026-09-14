defmodule DncWatchdogWeb.CommunicationCount do
  @moduledoc false

  alias DncWatchdog.Enforcement.CommunicationGroups

  def peer_key(communication), do: CommunicationGroups.peer_key(communication)

  def peer_counts(communications) when is_list(communications) do
    Enum.frequencies_by(communications, &peer_key/1)
  end

  def apply_to_cases(cases, min_comms, sort_by, sort_dir) do
    apply_count(cases, min_comms, sort_by, sort_dir, &length(&1.communications))
  end

  def apply_to_senders(senders, counts, min_comms, sort_by, sort_dir) when is_map(counts) do
    apply_count(senders, min_comms, sort_by, sort_dir, &Map.get(counts, &1.peer_key, 0))
  end

  def apply_to_communications(communications, min_comms, sort_by, sort_dir) do
    counts = peer_counts(communications)

    apply_count(communications, min_comms, sort_by, sort_dir, fn communication ->
      Map.get(counts, peer_key(communication), 0)
    end)
  end

  def apply_to_groups(groups, min_comms, sort_by, sort_dir) do
    apply_count(groups, min_comms, sort_by, sort_dir, &length(&1.communications))
  end

  def apply_count(items, min_comms, sort_by, sort_dir, count_fun)
      when is_list(items) and is_function(count_fun, 1) do
    items
    |> filter_min(min_comms, count_fun)
    |> maybe_sort(sort_by, sort_dir, count_fun)
  end

  defp filter_min(items, min, _fun) when min in [nil, 0], do: items

  defp filter_min(items, min, fun) when is_integer(min) and min > 0 do
    Enum.filter(items, &(fun.(&1) >= min))
  end

  defp maybe_sort(items, "communications", dir, fun) when dir in [:asc, :desc] do
    Enum.sort_by(items, fun, dir)
  end

  defp maybe_sort(items, _sort_by, _dir, _fun), do: items
end

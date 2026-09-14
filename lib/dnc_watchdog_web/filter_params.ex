defmodule DncWatchdogWeb.FilterParams do
  @moduledoc false

  alias DncWatchdog.Enforcement.SearchFilter
  alias DncWatchdog.Enforcement.Workflow

  def parse_search(params) when is_map(params) do
    SearchFilter.normalize(Map.get(params, "q", ""))
  end

  def parse_workflow(params) when is_map(params) do
    case Map.get(params, "workflow", "all") do
      phase when is_binary(phase) ->
        if Workflow.valid_phase?(phase), do: phase, else: "all"

      _ ->
        "all"
    end
  end

  @allowed_sorts ~w(communications)

  def min_comms_options do
    [
      {"Any count", nil},
      {"1+", 1},
      {"2+", 2},
      {"3+", 3},
      {"5+", 5}
    ]
  end

  def parse_min_comms(params) when is_map(params) do
    raw = Map.get(params, "min_comms", Map.get(params, :min_comms))

    case Integer.parse(to_string(raw || "")) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  def parse_sort_by(params) when is_map(params) do
    case Map.get(params, "sort", Map.get(params, :sort)) do
      sort when sort in @allowed_sorts -> sort
      _ -> nil
    end
  end

  def parse_sort_dir(params) when is_map(params) do
    case Map.get(params, "dir", Map.get(params, :dir)) do
      dir when dir in ["asc", :asc] -> :asc
      _ -> :desc
    end
  end

  def next_sort(current_by, current_dir, clicked_key) do
    if current_by == clicked_key do
      {clicked_key, toggle_sort_dir(current_dir)}
    else
      {clicked_key, :desc}
    end
  end

  def toggle_sort_dir(:asc), do: :desc
  def toggle_sort_dir(_), do: :asc

  def assign_count_sort(socket, params) when is_map(params) do
    socket
    |> Phoenix.Component.assign(:min_comms, parse_min_comms(params))
    |> Phoenix.Component.assign(:sort_by, parse_sort_by(params))
    |> Phoenix.Component.assign(:sort_dir, parse_sort_dir(params))
  end

  def count_sort_extras(assigns, overrides \\ []) do
    min_comms = Keyword.get(overrides, :min_comms, assigns[:min_comms])
    sort_by = Keyword.get(overrides, :sort_by, assigns[:sort_by])
    sort_dir = Keyword.get(overrides, :sort_dir, assigns[:sort_dir])

    [
      min_comms: min_comms,
      sort: sort_by,
      dir: if(sort_by, do: sort_dir)
    ]
  end

  def path(base_path, workflow_phase, search_query, extras \\ []) do
    params =
      query_params(workflow_phase, search_query)
      |> Map.merge(extra_params(extras))

    case params do
      %{} = params when map_size(params) == 0 ->
        base_path

      params ->
        base_path <> "?" <> URI.encode_query(params)
    end
  end

  defp query_params(workflow_phase, search_query) do
    %{}
    |> maybe_put("workflow", workflow_phase, "all")
    |> maybe_put("q", SearchFilter.normalize(search_query), "")
  end

  defp extra_params(extras) when is_list(extras) do
    extras = Map.new(extras)

    %{}
    |> maybe_put_extra("min_comms", extras[:min_comms] || extras["min_comms"])
    |> maybe_put_sort(
      extras[:sort] || extras[:sort_by] || extras["sort"],
      extras[:dir] || extras[:sort_dir] || extras["dir"]
    )
  end

  defp extra_params(_), do: %{}

  defp maybe_put_extra(params, _key, nil), do: params
  defp maybe_put_extra(params, _key, ""), do: params

  defp maybe_put_extra(params, key, value) when is_integer(value) and value > 0 do
    Map.put(params, key, Integer.to_string(value))
  end

  defp maybe_put_extra(params, key, value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> Map.put(params, key, Integer.to_string(n))
      _ -> params
    end
  end

  defp maybe_put_extra(params, key, value), do: Map.put(params, key, to_string(value))

  defp maybe_put_sort(params, sort, _dir) when sort in [nil, ""], do: params

  defp maybe_put_sort(params, sort, dir) do
    params
    |> Map.put("sort", to_string(sort))
    |> maybe_put("dir", dir_param(dir), "desc")
  end

  defp dir_param(dir) when dir in [:asc, "asc"], do: "asc"
  defp dir_param(dir) when dir in [:desc, "desc"], do: "desc"
  defp dir_param(_), do: "desc"

  defp maybe_put(params, _key, value, blank) when value in [nil, "", blank], do: params
  defp maybe_put(params, key, value, _blank), do: Map.put(params, key, value)

  def filter_checked?(filters, key) when is_map(filters) do
    Map.get(filters, key) == "true"
  end

  @doc """
  Returns `true`/`false` when `key` is present, otherwise `nil`.
  """
  def parse_optional_bool(params, key) when is_map(params) and is_binary(key) do
    case Map.fetch(params, key) do
      {:ok, value} -> value in [true, "true", "1"]
      :error -> nil
    end
  end

  def parse_peer(params) when is_map(params) do
    case SearchFilter.normalize(Map.get(params, "peer", "")) do
      "" -> nil
      peer -> peer
    end
  end
end

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

  def path(base_path, workflow_phase, search_query) do
    case query_params(workflow_phase, search_query) do
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

  defp maybe_put(params, _key, value, blank) when value in [nil, "", blank], do: params
  defp maybe_put(params, key, value, _blank), do: Map.put(params, key, value)
end

defmodule DncWatchdogWeb.FilterParamsTest do
  use ExUnit.Case, async: true

  alias DncWatchdogWeb.FilterParams

  describe "filter_checked?/2" do
    test "returns true when filter value is the string \"true\"" do
      assert FilterParams.filter_checked?(%{"violations_only" => "true"}, "violations_only")
    end

    test "returns false when filter value is the string \"false\"" do
      refute FilterParams.filter_checked?(%{"violations_only" => "false"}, "violations_only")
    end

    test "returns false when filter key is missing" do
      refute FilterParams.filter_checked?(%{}, "violations_only")
    end

    test "returns false for boolean true instead of string \"true\"" do
      refute FilterParams.filter_checked?(%{"violations_only" => true}, "violations_only")
    end

    test "returns false for nil value" do
      refute FilterParams.filter_checked?(%{"violations_only" => nil}, "violations_only")
    end

    test "returns false for empty string value" do
      refute FilterParams.filter_checked?(%{"violations_only" => ""}, "violations_only")
    end
  end

  describe "parse_optional_bool/2" do
    test "returns true for true-like query values" do
      assert FilterParams.parse_optional_bool(%{"include_excluded" => "true"}, "include_excluded")
      assert FilterParams.parse_optional_bool(%{"include_excluded" => "1"}, "include_excluded")
      assert FilterParams.parse_optional_bool(%{"include_excluded" => true}, "include_excluded")
    end

    test "returns false for other present values" do
      refute FilterParams.parse_optional_bool(
               %{"include_excluded" => "false"},
               "include_excluded"
             )
    end

    test "returns nil when the key is missing" do
      assert FilterParams.parse_optional_bool(%{}, "include_excluded") == nil
    end
  end

  describe "parse_peer/1" do
    test "returns a trimmed peer or nil" do
      assert FilterParams.parse_peer(%{"peer" => " 8005550000 "}) == "8005550000"
      assert FilterParams.parse_peer(%{}) == nil
      assert FilterParams.parse_peer(%{"peer" => "  "}) == nil
    end
  end

  describe "count sort params" do
    test "parses min_comms, sort, and dir" do
      assert FilterParams.parse_min_comms(%{"min_comms" => "2"}) == 2
      assert FilterParams.parse_min_comms(%{"min_comms" => ""}) == nil
      assert FilterParams.parse_sort_by(%{"sort" => "communications"}) == "communications"
      assert FilterParams.parse_sort_by(%{"sort" => "nope"}) == nil
      assert FilterParams.parse_sort_dir(%{"dir" => "asc"}) == :asc
      assert FilterParams.parse_sort_dir(%{}) == :desc
      assert FilterParams.next_sort(nil, :desc, "communications") == {"communications", :desc}

      assert FilterParams.next_sort("communications", :desc, "communications") ==
               {"communications", :asc}
    end

    test "path includes count sort extras" do
      path =
        FilterParams.path("/cases", "all", "",
          min_comms: 2,
          sort: "communications",
          dir: :asc
        )

      query = path |> URI.parse() |> Map.get(:query) |> URI.decode_query()

      assert query == %{
               "min_comms" => "2",
               "sort" => "communications",
               "dir" => "asc"
             }
    end

    test "path omits default desc dir" do
      path = FilterParams.path("/cases", "all", "", sort: "communications", dir: :desc)
      query = path |> URI.parse() |> Map.get(:query) |> URI.decode_query()
      assert query == %{"sort" => "communications"}
    end
  end
end

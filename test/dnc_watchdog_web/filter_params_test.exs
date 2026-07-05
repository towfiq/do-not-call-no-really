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
end

defmodule DncWatchdog.Enforcement.SelfInitiatedFilter do
  @moduledoc """
  Drops communications you initiated when `my_phone` is known.

  Outgoing SMS/calls are mapped with your number as `from_number`; those rows are
  not useful for unsolicited-contact tracking.
  """

  alias DncWatchdog.Enforcement.Phone

  @doc """
  When `my_phone` normalizes to a non-empty value, removes outgoing rows and any
  row whose `from_number` matches your phone.
  """
  def reject_self_initiated(rows, my_phone) do
    my = Phone.normalize(my_phone)

    if my == "" do
      {rows, 0}
    else
      {kept, skipped} =
        Enum.split_with(rows, fn row -> not self_initiated?(row, my) end)

      {kept, length(skipped)}
    end
  end

  @doc """
  True when the row is an outgoing communication or was sent/placed from `my_phone`.
  """
  def self_initiated_row?(row, my_phone) do
    my = Phone.normalize(my_phone)
    my != "" and self_initiated?(row, my)
  end

  defp self_initiated?(row, my) do
    cond do
      direction(row) == "outgoing" -> true
      Phone.normalize(from_number(row)) == my -> true
      true -> false
    end
  end

  defp direction(row), do: Map.get(row, :direction) || Map.get(row, "direction")
  defp from_number(row), do: Map.get(row, :from_number) || Map.get(row, "from_number")
end

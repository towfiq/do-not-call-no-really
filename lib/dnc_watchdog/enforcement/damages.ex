defmodule DncWatchdog.Enforcement.Damages do
  @moduledoc """
  Trial-rate statutory damages shown in list tables ($1,500 per violation).
  """

  alias DncWatchdog.Enforcement.FilingLimits

  def per_violation, do: FilingLimits.per_violation_damages()

  def zero, do: Decimal.new("0.00")

  def violation?(%{violation_status: "violation"}), do: true
  def violation?(_), do: false

  def for_communication(communication) do
    if violation?(communication), do: per_violation(), else: zero()
  end

  def count(communications) when is_list(communications) do
    Enum.count(communications, &violation?/1)
  end

  def for_count(n) when is_integer(n) and n >= 0 do
    Decimal.mult(per_violation(), Decimal.new(n))
  end

  def total(communications) when is_list(communications) do
    for_count(count(communications))
  end

  def for_case(%{communications: communications}) when is_list(communications) do
    total(communications)
  end

  def for_case(_), do: zero()

  def format(%Decimal{} = amount) do
    {whole, fraction} =
      amount
      |> Decimal.round(2)
      |> Decimal.to_string(:normal)
      |> split_decimal_string()

    "$#{commaize(whole)}.#{fraction}"
  end

  def format(n) when is_integer(n) and n >= 0, do: format(for_count(n))

  def format_row(communication) do
    if violation?(communication), do: format(for_communication(communication)), else: "—"
  end

  defp split_decimal_string(value) do
    case String.split(value, ".", parts: 2) do
      [whole] -> {whole, "00"}
      [whole, fraction] -> {whole, String.pad_trailing(fraction, 2, "0")}
    end
  end

  defp commaize(digits) do
    digits
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end

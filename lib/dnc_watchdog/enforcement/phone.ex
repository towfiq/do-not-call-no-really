defmodule DncWatchdog.Enforcement.Phone do
  @moduledoc """
  Normalizes phone numbers from strings, nil, or SQLite cell values.
  """

  def normalize(nil), do: ""
  def normalize(value) when is_binary(value), do: normalize_digits(value)
  def normalize(value) when is_integer(value), do: normalize_digits(Integer.to_string(value))
  def normalize(value), do: value |> to_string() |> normalize_digits()

  def normalize_or_env(nil), do: System.get_env("DNC_MY_PHONE") || ""
  def normalize_or_env(phone), do: normalize(phone)

  @doc """
  Returns lookup keys for matching a phone against Contacts or message peers.

  US numbers are indexed under both the 10-digit national form and the
  11-digit `1` + national form so `+1` prefixes in Contacts vs Messages
  still match.
  """
  def lookup_keys(value) do
    normalized = normalize(value)

    cond do
      normalized == "" ->
        []

      byte_size(normalized) == 10 ->
        [normalized, "1" <> normalized]

      byte_size(normalized) == 11 and String.starts_with?(normalized, "1") ->
        [String.slice(normalized, 1, 10), normalized]

      true ->
        [normalized]
    end
    |> Enum.uniq()
  end

  @doc """
  Returns true when `value` matches any lookup key in `phones`.
  """
  def contact_member?(value, phones) do
    Enum.any?(lookup_keys(value), &MapSet.member?(phones, &1))
  end

  defp normalize_digits(value) do
    digits = value |> String.to_charlist() |> Enum.filter(&(&1 in ?0..?9)) |> to_string()

    cond do
      String.length(digits) == 11 and String.starts_with?(digits, "1") ->
        String.slice(digits, 1, 10)

      true ->
        digits
    end
  end
end

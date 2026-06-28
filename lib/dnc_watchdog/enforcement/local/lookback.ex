defmodule DncWatchdog.Enforcement.Local.Lookback do
  @moduledoc """
  Computes lookback cutoffs for local SQLite imports.

  Messages `date` values may be seconds or nanoseconds since the Apple epoch
  (2001-01-01 UTC). Call history uses seconds.
  """

  @apple_epoch_seconds 978_307_200
  @nanosecond_threshold 1_000_000_000_000

  @doc """
  Returns a `NaiveDateTime` cutoff from `:since`, `:lookback_days`, or nil.
  """
  def since_from_opts(opts) do
    cond do
      since = Keyword.get(opts, :since) ->
        normalize_since(since)

      days = Keyword.get(opts, :lookback_days) ->
        case days do
          n when is_integer(n) and n > 0 ->
            utc_now() |> shift_days(-n)

          bin when is_binary(bin) ->
            case Integer.parse(bin) do
              {value, _} when value > 0 -> utc_now() |> shift_days(-value)
              _ -> nil
            end

          _ ->
            nil
        end

      true ->
        nil
    end
  end

  @doc """
  Keeps rows whose `timestamp` is on or after `since`.
  """
  def filter_rows(rows, nil), do: {rows, 0}

  def filter_rows(rows, %NaiveDateTime{} = since) do
    {kept, skipped} =
      Enum.split_with(rows, fn row ->
        NaiveDateTime.compare(row.timestamp, since) != :lt
      end)

    {kept, length(skipped)}
  end

  @doc """
  SQL fragment for Messages `date` column (seconds OR nanoseconds).
  """
  def messages_where_fragment(%NaiveDateTime{} = since) do
    min_seconds = min_apple_seconds(since)
    min_nanoseconds = min_apple_nanoseconds(since)

    """
    AND (
      (m.date >= #{@nanosecond_threshold} AND m.date >= #{min_nanoseconds})
      OR
      (m.date < #{@nanosecond_threshold} AND m.date >= #{min_seconds})
    )
    """
    |> String.trim()
  end

  def messages_where_fragment(_), do: ""

  @doc """
  Applies a SQL row cap only when there is no lookback cutoff.

  With `:since` / `--lookback-days`, the time window is the bound. Without one,
  `limit` prevents accidentally loading an entire lifetime of messages/calls.
  """
  def sql_limit_clause(%NaiveDateTime{}, _limit), do: ""
  def sql_limit_clause(_since, nil), do: ""

  def sql_limit_clause(_since, limit) when is_integer(limit) and limit > 0 do
    "LIMIT #{limit}"
  end

  def sql_limit_clause(_since, _limit), do: ""

  @doc """
  SQL fragment for call history date columns stored as Apple epoch seconds.
  """
  def calls_where_fragment(%NaiveDateTime{} = since, column) do
    "WHERE #{column} >= #{min_apple_seconds(since)}"
  end

  def calls_where_fragment(_, _column), do: ""

  def min_apple_seconds(%NaiveDateTime{} = since) do
    since
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix()
    |> Kernel.-(@apple_epoch_seconds)
  end

  def min_apple_nanoseconds(%NaiveDateTime{} = since) do
    min_apple_seconds(since) * 1_000_000_000
  end

  defp normalize_since(%NaiveDateTime{} = dt), do: dt

  defp normalize_since(%Date{} = date), do: NaiveDateTime.new!(date, ~T[00:00:00])

  defp normalize_since(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  defp normalize_since(_), do: nil

  defp shift_days(%NaiveDateTime{} = dt, days) do
    NaiveDateTime.add(dt, days * 86_400, :second)
  end

  defp utc_now do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_naive()
  end
end

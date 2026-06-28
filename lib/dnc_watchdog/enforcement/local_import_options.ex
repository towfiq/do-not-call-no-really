defmodule DncWatchdog.Enforcement.LocalImportOptions do
  @moduledoc """
  Builds options for `LocalImporter.import_local/1` from keywords, config, or env.
  """

  @doc """
  Normalizes import options from CLI flags, periodic-import config, or explicit keywords.
  """
  def build(opts \\ []) do
    lookback_days = resolve_lookback_days(opts)

    base =
      [
        messages: Keyword.get(opts, :messages, true),
        calls: Keyword.get(opts, :calls, true),
        skip_contacts: Keyword.get(opts, :skip_contacts, true),
        skip_self_initiated: Keyword.get(opts, :skip_self_initiated, true),
        messages_db: Keyword.get(opts, :messages_db),
        calls_db: Keyword.get(opts, :calls_db),
        contacts_db: Keyword.get(opts, :contacts_db),
        contacts_dbs: Keyword.get(opts, :contacts_dbs),
        limit: Keyword.get(opts, :limit, 5_000),
        my_phone: resolve_my_phone(opts),
        lookback_days: lookback_days,
        since: Keyword.get(opts, :since)
      ]

    since =
      base[:since] ||
        if lookback_days do
          DncWatchdog.Enforcement.Local.Lookback.since_from_opts(lookback_days: lookback_days)
        end

    limit = resolve_limit(opts, lookback_days, since)

    base
    |> Keyword.put(:since, since)
    |> Keyword.put(:limit, limit)
  end

  @doc """
  Returns `:no_cap` when a lookback window is active, otherwise the row cap for
  unbounded full-history scans.
  """
  def sql_row_cap(opts) do
    built = build(opts)

    case {Keyword.get(built, :since), Keyword.get(built, :limit)} do
      {%NaiveDateTime{}, nil} -> :no_cap
      {%NaiveDateTime{}, limit} when is_integer(limit) -> limit
      {_, limit} when is_integer(limit) -> limit
      _ -> :no_cap
    end
  end

  defp resolve_limit(_opts, _lookback_days, %NaiveDateTime{}), do: nil
  defp resolve_limit(_opts, lookback_days, _) when is_integer(lookback_days), do: nil

  defp resolve_limit(opts, _, _) do
    opts
    |> Keyword.get(:limit)
    |> case do
      nil ->
        case System.get_env("DNC_IMPORT_LIMIT") do
          nil -> 5_000
          env -> parse_positive_int(env) || 5_000
        end

      limit ->
        parse_positive_int(limit) || 5_000
    end
  end

  @doc """
  Builds options from application config (see `:periodic_import`).
  """
  def from_config(config) when is_list(config) do
    config
    |> Keyword.take([
      :messages,
      :calls,
      :skip_contacts,
      :skip_self_initiated,
      :messages_db,
      :calls_db,
      :contacts_db,
      :limit,
      :my_phone,
      :lookback_days,
      :since
    ])
    |> build()
  end

  defp resolve_my_phone(opts) do
    opts
    |> Keyword.get(:my_phone)
    |> case do
      nil -> System.get_env("DNC_MY_PHONE")
      value -> value
    end
  end

  defp resolve_lookback_days(opts) do
    case Keyword.fetch(opts, :lookback_days) do
      {:ok, days} ->
        parse_positive_int(days)

      :error ->
        case System.get_env("DNC_IMPORT_LOOKBACK_DAYS") do
          nil -> nil
          env -> parse_positive_int(env)
        end
    end
  end

  defp parse_positive_int(value) do
    case Integer.parse(to_string(value)) do
      {days, _} when days > 0 -> days
      _ -> nil
    end
  end
end

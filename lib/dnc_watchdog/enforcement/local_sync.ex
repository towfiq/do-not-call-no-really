defmodule DncWatchdog.Enforcement.LocalSync do
  @moduledoc """
  Incremental sync from local Messages and Call History databases.

  Stores the last successful sync time and only imports rows newer than that
  cutoff (with a configurable overlap buffer).

  Continuity can deliver both SMS and Call History to the Mac hours or days
  after the event. Incremental sync therefore uses multi-day overlap windows
  (`:overlap_seconds` for messages, `:call_overlap_seconds` for calls) so
  delayed copies are still imported; duplicates are skipped via fingerprint.
  """

  import Ecto.Query, warn: false

  alias DncWatchdog.Enforcement.LocalImportOptions
  alias DncWatchdog.Enforcement.LocalImporter
  alias DncWatchdog.Enforcement.LocalImportSync
  alias DncWatchdog.Repo

  # 3 days — Continuity SMS and Call History can lag well behind the event time.
  @default_overlap_seconds 259_200
  @default_call_overlap_seconds 259_200

  @doc """
  Returns the persisted sync state, or an empty struct when never synced.
  """
  def get_state do
    case Repo.one(from s in LocalImportSync, order_by: [desc: s.id], limit: 1) do
      nil -> %LocalImportSync{}
      state -> state
    end
  end

  @doc """
  Imports messages and calls from local macOS databases.

  On the first run, uses `:lookback_days` from `:local_sync` config. Later runs
  import only rows at or after the previous sync (minus overlap). Messages and
  calls both use multi-day overlaps by default to tolerate delayed Continuity.

  Pass `lookback_days: N` (or an explicit `since:`) to force a fixed window and
  ignore the incremental last-sync cutoff — useful when Continuity delivered
  older rows after a sync already advanced `last_synced_at`.
  """
  def sync(opts \\ []) do
    started_at = DateTime.utc_now() |> DateTime.truncate(:second)

    try do
      state = get_or_insert_state!()
      import_opts = build_import_opts(state, opts)

      case run_import(import_opts) do
        {:ok, summary} ->
          state = persist_success!(state, started_at, summary)
          {:ok, %{summary: summary, state: state}}

        {:error, reason, summary} ->
          persist_error!(state, started_at, reason, summary)
          {:error, reason}
      end
    rescue
      error ->
        message = Exception.message(error)
        persist_error!(get_or_insert_state!(), started_at, message, nil)
        {:error, message}
    end
  end

  @doc """
  Human-readable summary for flash messages.
  """
  def summary_message(%{} = summary) do
    created = Map.get(summary, :created_communications, 0)
    duplicates = Map.get(summary, :skipped_duplicates, 0)
    skipped_contacts = Map.get(summary, :skipped_contacts, 0)
    message_rows = Map.get(summary, :message_rows, 0)
    call_rows = Map.get(summary, :call_rows, 0)
    logs = Map.get(summary, :logs, [])

    newest_call_at = Map.get(summary, :newest_call_at)

    ["Imported #{created} new"]
    |> maybe_add_part(true, "scanned #{message_rows} message(s) + #{call_rows} call(s)")
    |> maybe_add_part(duplicates > 0, "#{duplicates} duplicate(s)")
    |> maybe_add_part(
      Enum.any?(logs, &match?({:contacts_disabled, _}, &1)),
      "including contacts"
    )
    |> maybe_add_part(
      skipped_contacts > 0,
      "#{skipped_contacts} contact(s) skipped — enable Include contacts to import them"
    )
    |> append_contacts_warning(logs)
    |> maybe_add_part(
      is_binary(newest_call_at) and newest_call_at != "",
      "newest Mac call #{newest_call_at}"
    )
    |> Enum.join(" · ")
  end

  @doc """
  Formats last sync time for UI display.
  """
  def format_last_sync(%LocalImportSync{last_synced_at: nil}), do: "Never synced"

  def format_last_sync(%LocalImportSync{last_synced_at: %DateTime{} = dt}) do
    Calendar.strftime(dt, "%b %-d, %Y at %-I:%M %p UTC")
  end

  def format_last_sync(_), do: "Never synced"

  defp build_import_opts(state, overrides) do
    config =
      Application.get_env(:dnc_watchdog, :local_sync, [])
      |> Keyword.drop([:overlap_seconds, :call_overlap_seconds])

    merged = Keyword.merge(config, overrides)
    built = LocalImportOptions.build(merged)

    cond do
      explicit_lookback_days?(overrides) ->
        # Explicit window wins over incremental last-sync cutoff.
        built
        |> Keyword.put(:calls_since, built[:since])
        |> Keyword.put(:limit, nil)

      Keyword.has_key?(overrides, :since) ->
        built
        |> Keyword.put_new(:calls_since, built[:since])
        |> Keyword.put(:limit, nil)

      true ->
        apply_since(built, state.last_synced_at)
    end
  end

  defp explicit_lookback_days?(opts) do
    case Keyword.get(opts, :lookback_days) do
      days when is_integer(days) and days > 0 -> true
      _ -> false
    end
  end

  defp apply_since(opts, nil), do: opts

  defp apply_since(opts, %DateTime{} = last_synced_at) do
    base = DateTime.to_naive(last_synced_at)
    since = NaiveDateTime.add(base, -overlap_seconds(), :second)
    calls_since = NaiveDateTime.add(base, -call_overlap_seconds(), :second)

    opts
    |> Keyword.put(:since, since)
    |> Keyword.put(:calls_since, calls_since)
    |> Keyword.put(:lookback_days, nil)
    |> Keyword.put(:limit, nil)
  end

  defp overlap_seconds do
    Application.get_env(:dnc_watchdog, :local_sync, [])
    |> Keyword.get(:overlap_seconds, @default_overlap_seconds)
  end

  defp call_overlap_seconds do
    Application.get_env(:dnc_watchdog, :local_sync, [])
    |> Keyword.get(:call_overlap_seconds, @default_call_overlap_seconds)
  end

  defp run_import(opts) do
    summary = LocalImporter.import_local(opts)

    errors =
      summary.logs
      |> Enum.filter(fn
        {:error, _, _, _} -> true
        _ -> false
      end)

    if errors == [] do
      {:ok, summary}
    else
      message =
        errors
        |> Enum.map(&format_log_error/1)
        |> Enum.join("; ")

      {:error, message, summary}
    end
  end

  defp format_log_error({:error, _module, path, reason}) do
    "#{Path.basename(to_string(path))}: #{reason}"
  end

  defp get_or_insert_state! do
    case Repo.one(from s in LocalImportSync, order_by: [desc: s.id], limit: 1) do
      %LocalImportSync{} = state ->
        state

      nil ->
        {:ok, state} =
          %LocalImportSync{}
          |> LocalImportSync.changeset(%{})
          |> Repo.insert()

        state
    end
  end

  defp persist_success!(state, started_at, summary) do
    attrs = %{
      last_synced_at: started_at,
      last_started_at: started_at,
      last_status: "ok",
      last_error: nil,
      last_message_rows: summary.message_rows,
      last_call_rows: summary.call_rows,
      last_created_communications: summary.created_communications,
      last_skipped_duplicates: Map.get(summary, :skipped_duplicates, 0)
    }

    state
    |> LocalImportSync.changeset(attrs)
    |> Repo.update!()
  end

  defp persist_error!(state, started_at, reason, summary) do
    attrs =
      %{
        last_started_at: started_at,
        last_status: "error",
        last_error: to_string(reason)
      }
      |> maybe_put_summary_fields(summary)

    state
    |> LocalImportSync.changeset(attrs)
    |> Repo.update!()
  end

  defp maybe_put_summary_fields(attrs, nil), do: attrs

  defp maybe_put_summary_fields(attrs, summary) do
    Map.merge(attrs, %{
      last_message_rows: summary.message_rows,
      last_call_rows: summary.call_rows,
      last_created_communications: summary.created_communications,
      last_skipped_duplicates: Map.get(summary, :skipped_duplicates, 0)
    })
  end

  defp maybe_add_part(parts, true, text), do: parts ++ [text]
  defp maybe_add_part(parts, false, _text), do: parts

  defp append_contacts_warning(parts, logs) do
    cond do
      Enum.any?(logs, &match?({:contacts_skipped, _}, &1)) ->
        parts ++ ["Contacts unavailable — known senders may have been imported"]

      Enum.any?(logs, &match?({:contacts_empty, _}, &1)) ->
        parts ++ ["No contacts loaded — check Full Disk Access for this app"]

      true ->
        parts
    end
  end
end

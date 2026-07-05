defmodule DncWatchdog.Enforcement.LocalSync do
  @moduledoc """
  Incremental sync from local Messages and Call History databases.

  Stores the last successful sync time and only imports rows newer than that
  cutoff (with a configurable overlap buffer).
  """

  import Ecto.Query, warn: false

  alias DncWatchdog.Enforcement.LocalImportOptions
  alias DncWatchdog.Enforcement.LocalImporter
  alias DncWatchdog.Enforcement.LocalImportSync
  alias DncWatchdog.Repo

  @default_overlap_seconds 3600

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
  import only rows at or after the previous sync (minus overlap).
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
    logs = Map.get(summary, :logs, [])

    ["Imported #{created} new communication(s)"]
    |> maybe_add_part(duplicates > 0, "#{duplicates} duplicate(s) skipped")
    |> maybe_add_part(skipped_contacts > 0, "#{skipped_contacts} from contacts skipped")
    |> append_contacts_warning(logs)
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
      |> Keyword.drop([:overlap_seconds])

    config
    |> Keyword.merge(overrides)
    |> LocalImportOptions.build()
    |> apply_since(state.last_synced_at)
  end

  defp apply_since(opts, nil), do: opts

  defp apply_since(opts, %DateTime{} = last_synced_at) do
    since =
      last_synced_at
      |> DateTime.to_naive()
      |> NaiveDateTime.add(-overlap_seconds(), :second)

    opts
    |> Keyword.put(:since, since)
    |> Keyword.put(:lookback_days, nil)
    |> Keyword.put(:limit, nil)
  end

  defp overlap_seconds do
    Application.get_env(:dnc_watchdog, :local_sync, [])
    |> Keyword.get(:overlap_seconds, @default_overlap_seconds)
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

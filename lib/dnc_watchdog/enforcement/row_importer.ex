defmodule DncWatchdog.Enforcement.RowImporter do
  @moduledoc """
  Imports normalized communication rows into cases + communications.
  """

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.Communication
  alias DncWatchdog.Enforcement.Phone

  @marketing_terms ~w(offer special discount free trial insurance loan debt warranty limited time act now)

  def import_rows(rows) do
    excluded_keys = Enforcement.excluded_peer_keys_set()

      Enum.reduce(
      rows,
      %{rows: 0, created_cases: 0, created_communications: 0, skipped_duplicates: 0, failed: 0},
      fn row, acc ->
        case import_row(row, excluded_keys) do
          {:ok, %{case_created: case_created?, duplicate: duplicate?}} ->
            %{
              rows: acc.rows + 1,
              created_cases: acc.created_cases + if(case_created?, do: 1, else: 0),
              created_communications:
                acc.created_communications + if(duplicate?, do: 0, else: 1),
              skipped_duplicates: acc.skipped_duplicates + if(duplicate?, do: 1, else: 0),
              failed: acc.failed
            }

          {:error, _reason} ->
            %{acc | rows: acc.rows + 1, failed: acc.failed + 1}
        end
      end
    )
  end

  def import_row(row, excluded_keys \\ Enforcement.excluded_peer_keys_set()) do
    company = company_label(row)

    with {:ok, case_record, case_created?} <- find_or_create_case(company),
         {:ok, duplicate?} <- import_row_for_case(case_record, row, excluded_keys) do
      {:ok, %{case_created: case_created?, duplicate: duplicate?}}
    end
  end

  defp import_row_for_case(case_record, row, excluded_keys) do
    reasons =
      row
      |> detect_reasons()
      |> Enum.join("; ")

    attrs =
      row
      |> Map.put(:case_id, case_record.id)
      |> Map.put(:reasons, reasons)
      |> Map.put(:violation_status, violation_status_for(row, excluded_keys))
      |> Map.update!(:timestamp, &coerce_timestamp/1)
      |> ensure_to_number()

    fingerprint = Communication.fingerprint(attrs)

    case Enforcement.get_communication_by_fingerprint(fingerprint) do
      %Communication{} ->
        {:ok, true}

      nil ->
        attrs = Map.put(attrs, :source_fingerprint, fingerprint)

        case Enforcement.create_communication(attrs) do
          {:ok, _} -> {:ok, false}
          {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
          {:error, _} = error -> error
        end
    end
  end

  defp ensure_to_number(%{direction: "incoming", to_number: to} = row) when to in [nil, ""] do
    my_phone = Phone.normalize_or_env(nil)
    Map.put(row, :to_number, if(my_phone != "", do: my_phone, else: "local"))
  end

  defp ensure_to_number(%{direction: "outgoing", from_number: from} = row) when from in [nil, ""] do
    my_phone = Phone.normalize_or_env(nil)
    Map.put(row, :from_number, if(my_phone != "", do: my_phone, else: from))
  end

  defp ensure_to_number(row), do: row

  defp find_or_create_case(company_name) do
    case Enforcement.list_cases() |> Enum.find(&(&1.company_name == company_name)) do
      %{} = case_record ->
        {:ok, case_record, false}

      nil ->
        case Enforcement.create_case(%{
               company_name: company_name,
               status: "new",
               workflow_step: "intake",
               notes: "Auto-created from import",
               letter_draft: ""
             }) do
          {:ok, case_record} -> {:ok, case_record, true}
          {:error, _} = error -> error
        end
    end
  end

  defp company_label(%{company: company, from_number: from, direction: direction}) do
    company = company |> to_string() |> String.trim()

    cond do
      company != "" -> company
      direction == "incoming" and from not in [nil, ""] -> "Caller #{from}"
      true -> "Unknown Company"
    end
  end

  defp detect_reasons(%{direction: "incoming", channel: channel, duration_seconds: duration, body: body}) do
    terms = @marketing_terms |> Enum.filter(&String.contains?(String.downcase(body || ""), &1))

    []
    |> maybe_add("incoming contact from unapproved number", true)
    |> maybe_add("contains marketing language: #{Enum.join(terms, ", ")}", terms != [])
    |> maybe_add("short call pattern common in robocall campaigns", channel == "call" and duration < 15)
  end

  defp detect_reasons(_), do: []

  defp maybe_add(list, value, true), do: [value | list]
  defp maybe_add(list, _value, false), do: list

  defp violation_status_for(row, excluded_keys) do
    if Enforcement.excluded_sender_row?(row, excluded_keys), do: "excluded", else: "pending"
  end

  defp coerce_timestamp(%NaiveDateTime{} = dt), do: dt

  defp coerce_timestamp(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(String.replace(value, " ", "T")) do
      {:ok, dt} -> dt
      _ -> ~N[1970-01-01 00:00:00]
    end
  end
end

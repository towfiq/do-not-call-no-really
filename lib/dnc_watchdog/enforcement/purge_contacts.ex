defmodule DncWatchdog.Enforcement.PurgeContacts do
  @moduledoc """
  Deletes stored communications whose peer appears in macOS Contacts.
  """

  import Ecto.Query, warn: false

  alias DncWatchdog.Enforcement.Case
  alias DncWatchdog.Enforcement.Communication
  alias DncWatchdog.Enforcement.ContactFilter
  alias DncWatchdog.Enforcement.Local.Contacts
  alias DncWatchdog.Enforcement.Local.Paths
  alias DncWatchdog.Repo

  @type summary :: %{
          total: non_neg_integer(),
          matched: non_neg_integer(),
          deleted: non_neg_integer(),
          cases_deleted: non_neg_integer(),
          remaining: non_neg_integer(),
          dry_run: boolean()
        }

  @doc """
  Removes communications matching `ContactFilter.contact_row?/2`.

  Loads macOS Contacts by default (see `contacts_db` / `contacts_dbs` opts).
  Pass `contact_set:` in tests. Returns `{:error, reason}` when contacts
  cannot be loaded.
  """
  @spec purge(keyword()) :: {:ok, summary()} | {:error, term()}
  def purge(opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)

    with {:ok, contact_set} <- load_contact_set(opts) do
      communications = Repo.all(from c in Communication, order_by: [asc: c.id])

      {to_remove, kept} =
        Enum.split_with(communications, fn comm ->
          ContactFilter.contact_row?(communication_row(comm), contact_set)
        end)

      deleted =
        if dry_run? do
          length(to_remove)
        else
          Enum.reduce(to_remove, 0, fn comm, count ->
            case Repo.delete(comm) do
              {:ok, _} -> count + 1
              {:error, _} -> count
            end
          end)
        end

      cases_deleted =
        if dry_run? do
          count_orphaned_cases(to_remove)
        else
          delete_orphaned_cases(to_remove)
        end

      {:ok,
       %{
         total: length(communications),
         matched: length(to_remove),
         deleted: deleted,
         cases_deleted: cases_deleted,
         remaining: length(kept),
         dry_run: dry_run?
       }}
    end
  end

  defp load_contact_set(opts) do
    case Keyword.get(opts, :contact_set) do
      set when is_map(set) ->
        {:ok, set}

      nil ->
        contacts_paths =
          case Keyword.get(opts, :contacts_dbs) do
            nil -> Keyword.get(opts, :contacts_db)
            paths -> paths
          end

        case Contacts.load(contacts_dbs: Paths.contacts_dbs(contacts_paths)) do
          {:ok, set, paths} when paths != [] ->
            if MapSet.size(set.phones) == 0 and MapSet.size(set.emails) == 0 do
              {:error, :contacts_empty}
            else
              {:ok, set}
            end

          {:ok, _set, []} ->
            {:error, :contacts_not_found}

          {:error, {:contacts_unreadable, _} = reason} ->
            {:error, reason}
        end
    end
  end

  defp communication_row(%Communication{} = comm) do
    %{
      direction: comm.direction,
      from_number: comm.from_number,
      to_number: comm.to_number
    }
  end

  defp count_orphaned_cases(communications_to_remove) do
    remove_ids = MapSet.new(Enum.map(communications_to_remove, & &1.id))

    communications_to_remove
    |> Enum.map(& &1.case_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.count(fn case_id ->
      case_comms = Repo.all(from c in Communication, where: c.case_id == ^case_id)
      Enum.all?(case_comms, &MapSet.member?(remove_ids, &1.id))
    end)
  end

  defp delete_orphaned_cases(communications) do
    communications
    |> Enum.map(& &1.case_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.reduce(0, fn case_id, count ->
      remaining =
        Repo.aggregate(from(c in Communication, where: c.case_id == ^case_id), :count)

      if remaining == 0 do
        case Repo.get(Case, case_id) do
          nil ->
            count

          case_record ->
            case Repo.delete(case_record) do
              {:ok, _} -> count + 1
              {:error, _} -> count
            end
        end
      else
        count
      end
    end)
  end
end

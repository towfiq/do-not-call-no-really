defmodule DncWatchdog.Enforcement.Dedupe do
  @moduledoc """
  Removes duplicate communications using the same fingerprint as imports.
  """

  import Ecto.Query, warn: false

  alias DncWatchdog.Enforcement.Communication
  alias DncWatchdog.Repo

  @type summary :: %{
          total: non_neg_integer(),
          duplicate_groups: non_neg_integer(),
          deleted: non_neg_integer(),
          fingerprints_backfilled: non_neg_integer(),
          dry_run: boolean()
        }

  @doc """
  Groups communications by `Communication.fingerprint/1`, keeps one row per
  group, deletes the rest, and backfills `source_fingerprint` on the keeper when
  missing.

  Pass `dry_run: true` to report what would happen without deleting or updating.
  """
  @spec dedupe_communications(keyword()) :: summary()
  def dedupe_communications(opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)

    communications =
      Communication
      |> order_by([c], asc: c.id)
      |> Repo.all()

    groups =
      communications
      |> Enum.group_by(&fingerprint_for/1)

    {duplicate_groups, deleted, backfilled} =
      Enum.reduce(groups, {0, 0, 0}, fn {_fingerprint, group},
                                        {groups_acc, deleted_acc, backfilled_acc} ->
        case group do
          [_] ->
            {groups_acc, deleted_acc, backfilled_acc}

          _ ->
            fingerprint = fingerprint_for(hd(group))
            keeper = pick_keeper(group, fingerprint)
            to_remove = Enum.reject(group, &(&1.id == keeper.id))

            backfilled_acc =
              if needs_fingerprint_backfill?(keeper, fingerprint) do
                if dry_run? do
                  backfilled_acc + 1
                else
                  case backfill_fingerprint(keeper, fingerprint) do
                    {:ok, _} -> backfilled_acc + 1
                    {:error, _} -> backfilled_acc
                  end
                end
              else
                backfilled_acc
              end

            deleted_acc =
              Enum.reduce(to_remove, deleted_acc, fn comm, count ->
                if dry_run? do
                  count + 1
                else
                  case Repo.delete(comm) do
                    {:ok, _} -> count + 1
                    {:error, _} -> count
                  end
                end
              end)

            {groups_acc + 1, deleted_acc, backfilled_acc}
        end
      end)

    %{
      total: length(communications),
      duplicate_groups: duplicate_groups,
      deleted: deleted,
      fingerprints_backfilled: backfilled,
      dry_run: dry_run?
    }
  end

  defp fingerprint_for(%Communication{} = comm), do: Communication.computed_fingerprint(comm)

  defp pick_keeper(group, fingerprint) do
    Enum.min_by(group, &keeper_sort_key(&1, fingerprint))
  end

  defp keeper_sort_key(comm, fingerprint) do
    fingerprint_rank =
      cond do
        comm.source_fingerprint == fingerprint -> 0
        comm.source_fingerprint -> 1
        true -> 2
      end

    {fingerprint_rank, comm.id}
  end

  defp needs_fingerprint_backfill?(comm, fingerprint) do
    comm.source_fingerprint != fingerprint
  end

  defp backfill_fingerprint(comm, fingerprint) do
    comm
    |> Communication.changeset(%{source_fingerprint: fingerprint})
    |> Repo.update()
  end
end

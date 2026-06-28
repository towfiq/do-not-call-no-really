defmodule DncWatchdog.Enforcement.CaseGroups do
  @moduledoc """
  Links multiple cases so communications from rotating caller IDs appear together.
  """

  import Ecto.Query, warn: false

  alias DncWatchdog.Enforcement.Case
  alias DncWatchdog.Enforcement.CaseGroup
  alias DncWatchdog.Enforcement.Communication
  alias DncWatchdog.Enforcement.EvidenceAttachment
  alias DncWatchdog.Repo

  @doc """
  Returns every case id in the same group as `case_id`, including `case_id` itself.
  """
  def case_ids_for_group(case_id) when is_integer(case_id) do
    case Repo.get(Case, case_id) do
      %Case{case_group_id: nil} ->
        [case_id]

      %Case{case_group_id: group_id} ->
        Case
        |> where([c], c.case_group_id == ^group_id)
        |> select([c], c.id)
        |> Repo.all()
    end
  end

  @doc """
  Lists other cases in the same group as `case_record`.
  """
  def list_linked_cases(%Case{} = case_record) do
    case case_record.case_group_id do
      nil ->
        []

      group_id ->
        Case
        |> where([c], c.case_group_id == ^group_id and c.id != ^case_record.id)
        |> order_by([c], asc: c.company_name)
        |> Repo.all()
    end
  end

  @doc """
  Puts two cases in the same group, creating or merging groups as needed.
  """
  def link_cases(%Case{} = case_a, %Case{} = case_b) do
    if case_a.id == case_b.id do
      {:error, :same_case}
    else
      Repo.transaction(fn ->
        group_id = resolve_group_id!(case_a, case_b)

        Enum.each([case_a, case_b], fn case_record ->
          if case_record.case_group_id != group_id do
            case case_record |> Case.changeset(%{case_group_id: group_id}) |> Repo.update() do
              {:ok, updated} -> updated
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end
        end)

        group_id
      end)
    end
  end

  @doc """
  Removes `case_record` from its group. Deletes the group when it becomes empty.
  """
  def unlink_case(%Case{} = case_record) do
    group_id = case_record.case_group_id

    with {:ok, updated} <-
           case_record |> Case.changeset(%{case_group_id: nil}) |> Repo.update() do
      if group_id, do: cleanup_empty_group(group_id)
      {:ok, updated}
    end
  end

  @doc """
  Moves communications and evidence from `source` into `target`, links any
  remaining grouped cases, and deletes `source`.
  """
  def merge_case_into(%Case{} = target, source_id) when is_integer(source_id) do
    source = Repo.get!(Case, source_id)

    if target.id == source.id do
      {:error, :same_case}
    else
      Repo.transaction(fn ->
        group_id =
          case link_cases(target, source) do
            {:ok, id} -> id
            {:error, reason} -> Repo.rollback(reason)
          end

        now = DateTime.utc_now() |> DateTime.truncate(:second)

        from(c in Communication, where: c.case_id == ^source.id)
        |> Repo.update_all(set: [case_id: target.id, updated_at: now])

        from(a in EvidenceAttachment, where: a.case_id == ^source.id)
        |> Repo.update_all(set: [case_id: target.id, updated_at: now])

        case Repo.delete(source) do
          {:ok, _} -> :ok
          {:error, changeset} -> Repo.rollback(changeset)
        end

        cleanup_empty_group(group_id)
        Repo.get!(Case, target.id)
      end)
    end
  end

  defp resolve_group_id!(%Case{} = case_a, %Case{} = case_b) do
    cond do
      case_a.case_group_id && case_a.case_group_id == case_b.case_group_id ->
        case_a.case_group_id

      case_a.case_group_id && case_b.case_group_id ->
        merge_groups!(case_a.case_group_id, case_b.case_group_id)
        case_a.case_group_id

      case_a.case_group_id ->
        case_a.case_group_id

      case_b.case_group_id ->
        case_b.case_group_id

      true ->
        case %CaseGroup{} |> CaseGroup.changeset(%{}) |> Repo.insert() do
          {:ok, group} -> group.id
          {:error, changeset} -> Repo.rollback(changeset)
        end
    end
  end

  defp merge_groups!(keep_id, drop_id) do
    from(c in Case, where: c.case_group_id == ^drop_id)
    |> Repo.update_all(set: [case_group_id: keep_id])

    case Repo.get(CaseGroup, drop_id) do
      nil -> :ok
      group -> Repo.delete!(group)
    end
  end

  defp cleanup_empty_group(group_id) do
    count =
      Case
      |> where([c], c.case_group_id == ^group_id)
      |> Repo.aggregate(:count, :id)

    if count == 0 do
      case Repo.get(CaseGroup, group_id) do
        nil -> :ok
        group -> Repo.delete(group)
      end
    end

    :ok
  end
end

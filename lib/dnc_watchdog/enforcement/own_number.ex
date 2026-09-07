defmodule DncWatchdog.Enforcement.OwnNumber do
  @moduledoc """
  Treats the claimant's phone as an inbox, not a caller.

  Incoming rows use `to_number` for the owner's phone. Matching that field as
  a "peer" collapses unrelated spam onto a `Caller {my_phone}` case.
  """

  import Ecto.Query, warn: false

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.Case
  alias DncWatchdog.Enforcement.Communication
  alias DncWatchdog.Enforcement.ContactFilter
  alias DncWatchdog.Enforcement.Phone
  alias DncWatchdog.Repo

  @type summary :: %{
          reassigned: non_neg_integer(),
          created_cases: non_neg_integer(),
          deleted_own_communications: non_neg_integer(),
          deleted_own_cases: non_neg_integer()
        }

  @doc """
  Lookup keys for the claimant phone from profile and `DNC_MY_PHONE`.
  """
  def keys_set do
    [Enforcement.get_claimant_profile().phone, System.get_env("DNC_MY_PHONE")]
    |> Enum.flat_map(&Phone.lookup_keys/1)
    |> MapSet.new()
  end

  def own_number?(peer, keys \\ nil) do
    keys = keys || keys_set()
    MapSet.size(keys) > 0 and Enum.any?(Phone.lookup_keys(peer), &MapSet.member?(keys, &1))
  end

  @doc """
  Moves communications off cases named for the owner's phone back onto
  per-caller cases, then deletes leftover self-contact rows and those cases.
  """
  @spec unwind_assignments() :: summary()
  def unwind_assignments do
    keys = keys_set()

    empty = %{
      reassigned: 0,
      created_cases: 0,
      deleted_own_communications: 0,
      deleted_own_cases: 0
    }

    if MapSet.size(keys) == 0 do
      empty
    else
      collapsed_ids = own_number_case_ids(keys)

      if collapsed_ids == [] do
        empty
      else
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        comms =
          Communication
          |> where([c], c.case_id in ^collapsed_ids)
          |> order_by([c], asc: c.id)
          |> Repo.all()

        summary =
          Enum.reduce(comms, empty, fn comm, acc ->
            unwind_communication(comm, keys, collapsed_ids, now, acc)
          end)

        deleted_own_cases = delete_empty_own_cases(collapsed_ids)
        %{summary | deleted_own_cases: deleted_own_cases}
      end
    end
  end

  defp unwind_communication(comm, keys, collapsed_ids, now, acc) do
    peer = comm |> ContactFilter.peer_for() |> to_string() |> String.trim()

    cond do
      peer in ["", "local"] or own_number?(peer, keys) ->
        Repo.delete!(comm)
        %{acc | deleted_own_communications: acc.deleted_own_communications + 1}

      true ->
        {dest, created?} = destination_case(peer, collapsed_ids)

        if dest.id == comm.case_id do
          acc
        else
          from(c in Communication, where: c.id == ^comm.id)
          |> Repo.update_all(set: [case_id: dest.id, updated_at: now])

          %{
            acc
            | reassigned: acc.reassigned + 1,
              created_cases: acc.created_cases + if(created?, do: 1, else: 0)
          }
        end
    end
  end

  defp destination_case(peer, collapsed_ids) do
    normalized = Phone.normalize(peer)

    cond do
      ContactFilter.email_peer?(peer) ->
        destination_email_case(peer, collapsed_ids)

      normalized == "" ->
        create_caller_case("Unknown Company")

      true ->
        destination_phone_case(normalized, collapsed_ids)
    end
  end

  defp destination_phone_case(normalized, collapsed_ids) do
    caller_label = "Caller #{normalized}"

    case Repo.get_by(Case, company_name: caller_label) do
      %Case{id: id} = case_record ->
        if id in collapsed_ids do
          create_caller_case(caller_label)
        else
          {case_record, false}
        end

      nil ->
        create_caller_case(caller_label)
    end
  end

  defp destination_email_case(email, collapsed_ids) do
    email = String.downcase(email)

    case_id =
      Communication
      |> where([c], c.direction == "incoming")
      |> where([c], fragment("lower(?)", c.from_number) == ^email)
      |> where([c], c.case_id not in ^collapsed_ids)
      |> order_by([c], asc: c.case_id)
      |> limit(1)
      |> select([c], c.case_id)
      |> Repo.one()

    if case_id do
      {Repo.get!(Case, case_id), false}
    else
      create_caller_case("Caller #{email}")
    end
  end

  defp create_caller_case(company_name) do
    {:ok, case_record} =
      Enforcement.create_case(%{
        company_name: company_name,
        status: "new",
        workflow_step: "intake",
        notes: "Restored from own-number case collapse",
        letter_draft: ""
      })

    {case_record, true}
  end

  defp own_number_case_ids(keys) do
    Case
    |> select([c], {c.id, c.company_name})
    |> Repo.all()
    |> Enum.filter(fn {_id, name} -> own_number_case_name?(name, keys) end)
    |> Enum.map(&elem(&1, 0))
  end

  defp own_number_case_name?(name, keys) when is_binary(name) do
    trimmed = String.trim(name)

    phone =
      case trimmed do
        "Caller " <> rest -> rest
        other -> other
      end

    own_number?(phone, keys)
  end

  defp own_number_case_name?(_, _), do: false

  defp delete_empty_own_cases(ids) do
    Enum.reduce(ids, 0, fn id, acc ->
      remaining =
        Communication
        |> where([c], c.case_id == ^id)
        |> Repo.aggregate(:count, :id)

      if remaining == 0 do
        case Repo.get(Case, id) do
          nil ->
            acc

          case_record ->
            Repo.delete!(case_record)
            acc + 1
        end
      else
        acc
      end
    end)
  end
end

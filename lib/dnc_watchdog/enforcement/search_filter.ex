defmodule DncWatchdog.Enforcement.SearchFilter do
  @moduledoc """
  Shared text search helpers for cases and communications list views.
  """

  import Ecto.Query, warn: false

  alias DncWatchdog.Enforcement.Case
  alias DncWatchdog.Enforcement.Communication
  alias DncWatchdog.Repo

  @doc """
  Normalizes user search input from forms or URL params.
  """
  def normalize(query) do
    query
    |> to_string()
    |> String.trim()
  end

  def present?(query), do: normalize(query) != ""

  defp needle(query), do: normalize(query) |> String.downcase()

  @doc """
  Applies a case-list search filter to an existing `Case` query.
  """
  def apply_case_search(query, search) do
    if present?(search) do
      where(query, ^case_search_dynamic(search))
    else
      query
    end
  end

  @doc """
  Applies a communication-list search filter to an existing `Communication` query.
  """
  def apply_communication_search(query, search) do
    if present?(search) do
      where(query, ^communication_search_dynamic(search))
    else
      query
    end
  end

  defp case_search_dynamic(search) do
    n = needle(search)
    phone_ids = phone_matching_case_ids(search)

    name_match = dynamic([c], fragment("instr(lower(?), ?) > 0", c.company_name, ^n))
    notes_match = dynamic([c], fragment("instr(lower(?), ?) > 0", coalesce(c.notes, ""), ^n))
    status_match = dynamic([c], fragment("instr(lower(?), ?) > 0", c.status, ^n))
    step_match = dynamic([c], fragment("instr(lower(?), ?) > 0", c.workflow_step, ^n))
    claimant_match = dynamic([c], fragment("instr(lower(?), ?) > 0", coalesce(c.claimant_name, ""), ^n))
    phone_match = dynamic([c], fragment("instr(lower(?), ?) > 0", coalesce(c.claimant_phone, ""), ^n))
    email_match = dynamic([c], fragment("instr(lower(?), ?) > 0", coalesce(c.claimant_email, ""), ^n))

    comm_phone_match =
      if phone_ids == [] do
        dynamic(false)
      else
        dynamic([c], c.id in ^phone_ids)
      end

    id_match =
      case Integer.parse(normalize(search)) do
        {id, ""} -> dynamic([c], c.id == ^id)
        _ -> dynamic(false)
      end

    dynamic(
      [c],
      ^name_match or ^notes_match or ^status_match or ^step_match or ^claimant_match or
        ^phone_match or ^email_match or ^comm_phone_match or ^id_match
    )
  end

  defp communication_search_dynamic(search) do
    n = needle(search)
    digits = digits_only(search)
    like_digits = if digits == "", do: nil, else: "%#{digits}%"

    from_match =
      if like_digits do
        dynamic(
          [c],
          like(
            fragment(
              "replace(replace(replace(replace(replace(replace(?, '+', ''), ' ', ''), '-', ''), '(', ''), ')', ''), '.', '')",
              c.from_number
            ),
            ^like_digits
          )
        )
      else
        dynamic(false)
      end

    to_match =
      if like_digits do
        dynamic(
          [c],
          like(
            fragment(
              "replace(replace(replace(replace(replace(replace(?, '+', ''), ' ', ''), '-', ''), '(', ''), ')', ''), '.', '')",
              c.to_number
            ),
            ^like_digits
          )
        )
      else
        dynamic(false)
      end

    body_match = dynamic([c], fragment("instr(lower(?), ?) > 0", coalesce(c.body, ""), ^n))
    company_match = dynamic([c], fragment("instr(lower(?), ?) > 0", coalesce(c.company, ""), ^n))
    channel_match = dynamic([c], fragment("instr(lower(?), ?) > 0", c.channel, ^n))

    case_company_match =
      dynamic(
        [c],
        c.case_id in subquery(
          from(case in Case,
            where: fragment("instr(lower(?), ?) > 0", case.company_name, ^n),
            select: case.id
          )
        )
      )

    case_id_match =
      case Integer.parse(normalize(search)) do
        {id, ""} -> dynamic([c], c.case_id == ^id)
        _ -> dynamic(false)
      end

    dynamic(
      [c],
      ^from_match or ^to_match or ^body_match or ^company_match or ^channel_match or
        ^case_company_match or ^case_id_match
    )
  end

  defp phone_matching_case_ids(search) do
    digits = digits_only(search)

    if digits == "" do
      []
    else
      like = "%#{digits}%"

      Communication
      |> where([comm], comm.direction == "incoming")
      |> where(
        [comm],
        like(
          fragment(
            "replace(replace(replace(replace(replace(replace(?, '+', ''), ' ', ''), '-', ''), '(', ''), ')', ''), '.', '')",
            comm.from_number
          ),
          ^like
        )
      )
      |> group_by([comm], comm.case_id)
      |> select([comm], comm.case_id)
      |> Repo.all()
    end
  end

  defp digits_only(value) do
    value
    |> normalize()
    |> String.replace(~r/[^0-9]/, "")
  end
end

defmodule DncWatchdog.Enforcement do
  @moduledoc """
  The Enforcement context.
  """

  import Ecto.Query, warn: false
  require Logger
  alias DncWatchdog.Repo

  alias DncWatchdog.Enforcement.Case
  alias DncWatchdog.Enforcement.ClaimantProfile
  alias DncWatchdog.Enforcement.Communication
  alias DncWatchdog.Enforcement.ContactFilter
  alias DncWatchdog.Enforcement.ExcludedSender
  alias DncWatchdog.Enforcement.Phone
  alias DncWatchdog.Enforcement.EvidenceAttachment
  alias DncWatchdog.Enforcement.EvidenceStorage
  alias DncWatchdog.Enforcement.LegalEntity
  alias DncWatchdog.Enforcement.LetterDraft
  alias DncWatchdog.Enforcement.CourtFilingDraft
  alias DncWatchdog.Enforcement.CivilComplaintDraft
  alias DncWatchdog.Enforcement.FilingLimits
  alias DncWatchdog.Enforcement.Local.MeCard
  alias DncWatchdog.Enforcement.UspsTracking
  alias DncWatchdog.Enforcement.UspsBrowserHelper
  alias DncWatchdog.Enforcement.CaseGroups
  alias DncWatchdog.Enforcement.ContactCache
  alias DncWatchdog.Enforcement.OwnNumber
  alias DncWatchdog.Enforcement.Workflow
  alias DncWatchdog.Enforcement.SearchFilter

  def list_cases(opts \\ []) do
    Case
    |> order_by([c], desc: c.inserted_at)
    |> apply_case_filters(opts)
    |> maybe_preload_communications(opts)
    |> maybe_preload_legal_entity(opts)
    |> Repo.all()
  end

  def count_cases(opts \\ []) do
    Case
    |> apply_case_filters(opts)
    |> Repo.aggregate(:count, :id)
  end

  defp apply_case_filters(query, opts) do
    query
    |> maybe_filter_workflow_steps(workflow_steps_opt(opts))
    |> maybe_require_violations(Keyword.get(opts, :require_violations, false))
    |> SearchFilter.apply_case_search(Keyword.get(opts, :search))
  end

  defp maybe_require_violations(query, true) do
    violation_case_ids =
      from comm in Communication,
        where: comm.violation_status == "violation",
        group_by: comm.case_id,
        select: comm.case_id

    group_ids_with_violations =
      from comm in Communication,
        join: comm_case in Case,
        on: comm.case_id == comm_case.id,
        where: comm.violation_status == "violation",
        where: not is_nil(comm_case.case_group_id),
        group_by: comm_case.case_group_id,
        select: comm_case.case_group_id

    query
    |> where(
      [c],
      c.id in subquery(violation_case_ids) or
        (not is_nil(c.case_group_id) and c.case_group_id in subquery(group_ids_with_violations))
    )
  end

  defp maybe_require_violations(query, _), do: query

  defp workflow_steps_opt(opts) do
    case Keyword.get(opts, :workflow_phase) do
      phase when is_binary(phase) ->
        Workflow.steps_for_phase(phase)

      _ ->
        Keyword.get(opts, :workflow_steps)
    end
  end

  defp maybe_filter_workflow_steps(query, steps) when is_list(steps) and steps != [] do
    where(query, [c], c.workflow_step in ^steps)
  end

  defp maybe_filter_workflow_steps(query, _), do: query

  defp maybe_preload_communications(query, opts) do
    if Keyword.get(opts, :preload_communications),
      do: preload(query, :communications),
      else: query
  end

  defp maybe_preload_legal_entity(query, opts) do
    if Keyword.get(opts, :preload_legal_entity), do: preload(query, :legal_entity), else: query
  end

  def get_case!(id) do
    Case
    |> preload([:communications, :legal_entity, :evidence_attachments, :case_group])
    |> Repo.get!(id)
  end

  def create_case(attrs \\ %{}) do
    %Case{}
    |> Case.changeset(attrs)
    |> Repo.insert()
  end

  def update_case(%Case{} = case, attrs) do
    case
    |> Case.changeset(attrs)
    |> Repo.update()
  end

  def delete_case(%Case{} = case) do
    Repo.delete(case)
  end

  def change_case(%Case{} = case, attrs \\ %{}) do
    Case.changeset(case, attrs)
  end

  def list_case_communications(case_id, opts \\ []) do
    case_id
    |> communications_query(opts)
    |> preload(case: :legal_entity)
    |> Repo.all()
    |> maybe_hide_contact_communications(opts)
  end

  def list_communications(opts \\ []) do
    limit = Keyword.get(opts, :limit, 1_000)
    hide_contacts? = Keyword.get(opts, :hide_contacts, false)

    fetch_limit = if hide_contacts?, do: max(limit * 5, 5_000), else: limit

    opts
    |> Keyword.put(:limit, fetch_limit)
    |> communications_query()
    |> preload(case: :legal_entity)
    |> Repo.all()
    |> maybe_hide_contact_communications(opts)
    |> Enum.take(limit)
  end

  defp communications_query(case_id, opts) when is_integer(case_id) do
    case_ids = CaseGroups.case_ids_for_group(case_id)

    from(c in Communication, where: c.case_id in ^case_ids, order_by: [desc: c.timestamp])
    |> apply_communication_filters(opts)
  end

  defp communications_query(opts) do
    limit = Keyword.fetch!(opts, :limit)

    Communication
    |> order_by([c], desc: c.timestamp)
    |> limit(^limit)
    |> apply_communication_filters(opts)
  end

  defp apply_communication_filters(query, opts) do
    query
    |> maybe_violations_only(Keyword.get(opts, :violations_only, false))
    |> maybe_hide_excluded(Keyword.get(opts, :hide_excluded, true))
    |> maybe_hide_spam(Keyword.get(opts, :hide_spam, false))
    |> maybe_filter_case_workflow_steps(workflow_steps_opt(opts))
    |> SearchFilter.apply_communication_search(Keyword.get(opts, :search))
  end

  defp maybe_filter_case_workflow_steps(query, steps) when is_list(steps) and steps != [] do
    query
    |> join(:inner, [c], case in assoc(c, :case))
    |> where([c, case], case.workflow_step in ^steps)
  end

  defp maybe_filter_case_workflow_steps(query, _), do: query

  defp maybe_violations_only(query, true) do
    where(query, [c], c.violation_status == "violation")
  end

  defp maybe_violations_only(query, _), do: query

  defp maybe_hide_excluded(query, true) do
    where(query, [c], c.violation_status != "excluded")
  end

  defp maybe_hide_excluded(query, _), do: query

  defp maybe_hide_spam(query, true) do
    where(query, [c], c.spam == false)
  end

  defp maybe_hide_spam(query, _), do: query

  defp maybe_hide_contact_communications(communications, opts) do
    if Keyword.get(opts, :hide_contacts, false) do
      case contact_set_for_filter(opts) do
        {:ok, contact_set} ->
          ContactFilter.reject_contact_communications(communications, contact_set)

        :error ->
          communications
      end
    else
      communications
    end
  end

  defp contact_set_for_filter(opts) do
    case Keyword.get(opts, :contact_set) do
      set when is_map(set) ->
        {:ok, set}

      nil ->
        set = ContactCache.get_set()

        if MapSet.size(set.phones) == 0 and MapSet.size(set.emails) == 0 do
          :error
        else
          {:ok, set}
        end
    end
  end

  def count_communications(opts \\ []) do
    if Keyword.get(opts, :hide_contacts, false) do
      count_hiding_contacts(opts)
    else
      Communication
      |> apply_communication_filters(opts)
      |> Repo.aggregate(:count, :id)
    end
  end

  defp count_hiding_contacts(opts) do
    rows =
      opts
      |> Keyword.put(:limit, 50_000)
      |> communications_query()
      |> select([c], {c.direction, c.from_number, c.to_number})
      |> Repo.all()
      |> Enum.map(fn {direction, from, to} ->
        %{direction: direction, from_number: from || "", to_number: to || ""}
      end)

    case contact_set_for_filter(opts) do
      {:ok, contact_set} ->
        rows
        |> Enum.reject(&ContactFilter.contact_row?(&1, contact_set))
        |> length()

      :error ->
        length(rows)
    end
  end

  def get_communication!(id), do: Repo.get!(Communication, id)

  def get_communication_by_fingerprint(fingerprint) do
    Repo.get_by(Communication, source_fingerprint: fingerprint)
  end

  @doc """
  Finds an existing communication matching import attrs, including rows with
  stale or missing `source_fingerprint` values.
  """
  def find_communication_duplicate(attrs) when is_map(attrs) do
    fingerprint = Communication.fingerprint(attrs)

    case get_communication_by_fingerprint(fingerprint) do
      %Communication{} = comm ->
        comm

      nil ->
        attrs
        |> duplicate_candidates()
        |> Enum.find(&(Communication.computed_fingerprint(&1) == fingerprint))
    end
  end

  def backfill_communication_fingerprint(%Communication{} = comm, fingerprint) do
    if comm.source_fingerprint == fingerprint do
      {:ok, comm}
    else
      update_communication(comm, %{source_fingerprint: fingerprint})
    end
  end

  defp duplicate_candidates(attrs) do
    timestamp = attrs[:timestamp] || attrs["timestamp"]
    channel = attrs[:channel] || attrs["channel"]
    direction = attrs[:direction] || attrs["direction"]
    peer = import_peer(attrs)

    query =
      Communication
      |> where([c], c.timestamp == ^timestamp)
      |> where([c], c.channel == ^channel)
      |> where([c], c.direction == ^direction)

    if peer == "" do
      Repo.all(query)
    else
      keys = Phone.lookup_keys(peer)

      match =
        Enum.reduce(keys, dynamic(false), fn key, acc ->
          dynamic(
            [c],
            ^acc or
              fragment(
                "replace(replace(replace(replace(replace(replace(?, '+', ''), ' ', ''), '-', ''), '(', ''), ')', ''), '.', '') = ?",
                c.from_number,
                ^key
              ) or
              fragment(
                "replace(replace(replace(replace(replace(replace(?, '+', ''), ' ', ''), '-', ''), '(', ''), ')', ''), '.', '') = ?",
                c.to_number,
                ^key
              )
          )
        end)

      query |> where(^match) |> Repo.all()
    end
  end

  defp import_peer(attrs) do
    direction = attrs[:direction] || attrs["direction"]

    peer =
      case direction do
        "incoming" -> attrs[:from_number] || attrs["from_number"]
        "outgoing" -> attrs[:to_number] || attrs["to_number"]
        _ -> ""
      end

    Phone.normalize(peer)
  end

  def create_communication(attrs \\ %{}) do
    %Communication{}
    |> Communication.changeset(attrs)
    |> Repo.insert()
  end

  def update_communication(%Communication{} = communication, attrs) do
    communication
    |> Communication.changeset(attrs)
    |> Repo.update()
  end

  def set_communication_violation_status(%Communication{} = communication, status)
      when status in ["pending", "violation", "excluded"] do
    update_communication(communication, %{violation_status: status})
  end

  def set_communication_spam(%Communication{} = communication, spam) when is_boolean(spam) do
    update_communication(communication, %{spam: spam})
  end

  @doc """
  Counts all communications from the same peer (phone or email), regardless of filters.
  """
  def count_communications_for_peer(peer) do
    peer
    |> peer_query()
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Marks every communication from `peer` as not a violation and remembers the sender
  for future imports.

  Returns `{:ok, count}`, `{:error, :empty_peer}`, or `{:error, :invalid_peer}`.
  """
  def exclude_all_from_peer(peer) do
    peer = peer |> to_string() |> String.trim()

    cond do
      peer == "" ->
        {:error, :empty_peer}

      true ->
        case ExcludedSender.classify_peer(peer) do
          :invalid ->
            {:error, :invalid_peer}

          _ ->
            {:ok, _sender} = add_excluded_sender(peer)

            now = DateTime.utc_now() |> DateTime.truncate(:second)

            {count, _} =
              peer
              |> peer_query()
              |> Repo.update_all(set: [violation_status: "excluded", updated_at: now])

            {:ok, count}
        end
    end
  end

  def exclude_all_from_peer_for_communication(%Communication{} = communication) do
    communication |> ContactFilter.peer_for() |> exclude_all_from_peer()
  end

  @doc """
  Returns all senders excluded from violation review (applied on future imports too).
  """
  def list_excluded_senders do
    ExcludedSender
    |> order_by([s], asc: s.display_peer)
    |> Repo.all()
  end

  @doc """
  Adds a sender to the excluded list. Idempotent for the same peer.
  """
  def add_excluded_sender(raw_peer) do
    case ExcludedSender.classify_peer(raw_peer) do
      :invalid ->
        {:error, :invalid_peer}

      {peer_type, peer_key, display_peer} ->
        attrs = %{
          peer_type: Atom.to_string(peer_type),
          peer_key: peer_key,
          display_peer: display_peer
        }

        case Repo.get_by(ExcludedSender, peer_key: peer_key) do
          %ExcludedSender{} = existing ->
            {:ok, existing}

          nil ->
            %ExcludedSender{}
            |> ExcludedSender.changeset(attrs)
            |> Repo.insert()
        end
    end
  end

  def remove_excluded_sender(%ExcludedSender{} = sender) do
    Repo.delete(sender)
  end

  def remove_excluded_sender!(id) do
    ExcludedSender |> Repo.get!(id) |> Repo.delete!()
  end

  @doc """
  MapSet of peer keys for batch import filtering.
  """
  def excluded_peer_keys_set do
    ExcludedSender
    |> select([s], s.peer_key)
    |> Repo.all()
    |> MapSet.new()
  end

  def excluded_sender?(raw_peer) do
    key = ExcludedSender.peer_key(raw_peer)
    key != "" and Repo.exists?(from s in ExcludedSender, where: s.peer_key == ^key)
  end

  def excluded_sender_row?(row, excluded_keys \\ excluded_peer_keys_set()) do
    key = ExcludedSender.peer_key_for(row)
    key != "" and MapSet.member?(excluded_keys, key)
  end

  @doc """
  Reassigns every communication matching `peer` (any case) onto `case_id`.

  Used when merging cases so messages/calls imported under the wrong case
  still move with the defendant being merged in.
  """
  def reassign_peer_communications_to_case(peer, case_id)
      when is_binary(peer) and is_integer(case_id) do
    peer = String.trim(peer)

    if peer == "" do
      0
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {count, _} =
        peer
        |> peer_query()
        |> Repo.update_all(set: [case_id: case_id, updated_at: now])

      count
    end
  end

  defp peer_query(peer) do
    if ContactFilter.email_peer?(peer) do
      email = String.downcase(peer)

      from c in Communication,
        where:
          (c.direction == "incoming" and fragment("lower(?)", c.from_number) == ^email) or
            (c.direction == "outgoing" and fragment("lower(?)", c.to_number) == ^email)
    else
      normalized = Phone.normalize(peer)
      keys = Phone.lookup_keys(normalized)

      if keys == [] do
        from c in Communication, where: false
      else
        match =
          Enum.reduce(keys, dynamic(false), fn key, acc ->
            dynamic(
              [c],
              ^acc or
                (c.direction == "incoming" and
                   fragment(
                     "replace(replace(replace(replace(replace(replace(?, '+', ''), ' ', ''), '-', ''), '(', ''), ')', ''), '.', '') = ?",
                     c.from_number,
                     ^key
                   )) or
                (c.direction == "outgoing" and
                   fragment(
                     "replace(replace(replace(replace(replace(replace(?, '+', ''), ' ', ''), '-', ''), '(', ''), ')', ''), '.', '') = ?",
                     c.to_number,
                     ^key
                   ))
            )
          end)

        from c in Communication, where: ^match
      end
    end
  end

  def list_violation_communications(case_id) do
    list_case_communications(case_id, hide_excluded: true, violations_only: true)
  end

  @doc """
  Finds an existing case for an incoming caller/sender phone or email peer.
  """
  def find_case_for_incoming_peer(peer) when is_binary(peer) do
    peer = String.trim(peer)

    cond do
      peer == "" ->
        nil

      OwnNumber.own_number?(peer) ->
        nil

      ContactFilter.email_peer?(peer) ->
        find_case_for_incoming_email(peer)

      true ->
        find_case_for_incoming_phone(peer)
    end
  end

  def find_case_for_incoming_peer(_), do: nil

  def own_phone_keys_set, do: OwnNumber.keys_set()

  def own_number?(peer, keys \\ nil), do: OwnNumber.own_number?(peer, keys)

  @doc """
  Splits communications that were collapsed onto a `Caller {my_phone}` case.
  """
  def unwind_own_number_case_assignments, do: OwnNumber.unwind_assignments()

  @doc """
  Moves communications from the same incoming peer onto one canonical case.

  Fixes imports where Call History used a display name while SMS used `Caller {phone}`.
  """
  def reconcile_incoming_peer_case_assignments do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    own_keys = OwnNumber.keys_set()

    peers =
      Communication
      |> where([c], c.direction == "incoming")
      |> select([c], c.from_number)
      |> Repo.all()
      |> Enum.map(&Phone.normalize/1)
      |> Enum.reject(&(&1 == "" or OwnNumber.own_number?(&1, own_keys)))
      |> Enum.uniq()

    Enum.reduce(peers, %{peers: 0, reassigned: 0}, fn peer, acc ->
      case reconcile_incoming_peer(peer, now) do
        {0, _} -> acc
        {count, _} -> %{acc | peers: acc.peers + 1, reassigned: acc.reassigned + count}
      end
    end)
  end

  defp find_case_for_incoming_phone(peer) do
    normalized = Phone.normalize(peer)

    if normalized == "" do
      nil
    else
      caller_label = "Caller #{normalized}"

      case Repo.get_by(Case, company_name: caller_label) do
        %Case{} = case_record ->
          case_record

        nil ->
          case incoming_peer_case_id(normalized) do
            nil -> nil
            case_id -> Repo.get(Case, case_id)
          end
      end
    end
  end

  defp find_case_for_incoming_email(email) do
    email = String.downcase(email)

    case_id =
      Communication
      |> where([c], c.direction == "incoming")
      |> where([c], fragment("lower(?)", c.from_number) == ^email)
      |> order_by([c], asc: c.case_id)
      |> limit(1)
      |> select([c], c.case_id)
      |> Repo.one()

    if case_id, do: Repo.get(Case, case_id)
  end

  defp incoming_peer_case_id(normalized) do
    keys = Phone.lookup_keys(normalized)

    match =
      Enum.reduce(keys, dynamic(false), fn key, acc ->
        dynamic(
          [c],
          ^acc or
            fragment(
              "replace(replace(replace(replace(replace(replace(?, '+', ''), ' ', ''), '-', ''), '(', ''), ')', ''), '.', '') = ?",
              c.from_number,
              ^key
            )
        )
      end)

    Communication
    |> where([c], c.direction == "incoming")
    |> where(^match)
    |> order_by([c], asc: c.case_id)
    |> limit(1)
    |> select([c], c.case_id)
    |> Repo.one()
  end

  defp reconcile_incoming_peer(peer, now) do
    query = peer_query(peer)

    case_ids =
      query
      |> select([c], c.case_id)
      |> Repo.all()
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case case_ids do
      [] ->
        {0, nil}

      [_single] ->
        {0, nil}

      ids ->
        canonical_id = canonical_case_id(peer, ids)

        {count, _} =
          query
          |> where([c], c.case_id != ^canonical_id)
          |> Repo.update_all(set: [case_id: canonical_id, updated_at: now])

        {count, canonical_id}
    end
  end

  defp canonical_case_id(peer, case_ids) do
    normalized = Phone.normalize(peer)
    caller_label = if normalized != "", do: "Caller #{normalized}", else: nil
    cases = Repo.all(from c in Case, where: c.id in ^case_ids, order_by: [asc: c.id])

    case Enum.find(cases, &(caller_label && &1.company_name == caller_label)) do
      %Case{id: id} ->
        id

      nil ->
        case Enum.find(cases, &caller_case_name?/1) do
          %Case{id: id} ->
            id

          nil ->
            case Enum.find(cases, &display_name_case?/1) do
              %Case{id: id} -> id
              nil -> hd(cases).id
            end
        end
    end
  end

  defp caller_case_name?(%Case{company_name: "Caller " <> _}), do: true
  defp caller_case_name?(_), do: false

  defp display_name_case?(%Case{company_name: name}) do
    name not in ["", "Unknown Company"] and not caller_case_name?(%Case{company_name: name})
  end

  def change_legal_entity(%LegalEntity{} = entity \\ %LegalEntity{}, attrs \\ %{}) do
    LegalEntity.changeset(entity, attrs)
  end

  def upsert_case_legal_entity(%Case{} = case, attrs) do
    entity =
      case case.legal_entity do
        %LegalEntity{} = existing -> existing
        _ -> %LegalEntity{}
      end

    with {:ok, entity} <-
           entity
           |> LegalEntity.changeset(attrs)
           |> Repo.insert_or_update(),
         {:ok, updated_case} <- update_case(case, %{legal_entity_id: entity.id}) do
      {:ok, Repo.preload(updated_case, :legal_entity, force: true)}
    end
  end

  def list_case_attachments(case_id) do
    Repo.all(
      from a in EvidenceAttachment,
        where: a.case_id == ^case_id,
        order_by: [asc: a.inserted_at],
        preload: :communication
    )
  end

  def create_evidence_attachment!(attrs) do
    %EvidenceAttachment{}
    |> EvidenceAttachment.changeset(attrs)
    |> Repo.insert!()
  end

  def delete_evidence_attachment(%EvidenceAttachment{} = attachment) do
    EvidenceStorage.delete_file(attachment)
    Repo.delete(attachment)
  end

  def get_evidence_attachment!(id), do: Repo.get!(EvidenceAttachment, id)

  def store_evidence_upload!(case_id, filename, binary, content_type, attrs \\ %{}) do
    {storage_path, _stored_name} = EvidenceStorage.store!(case_id, filename, binary, content_type)

    create_evidence_attachment!(
      Map.merge(
        %{
          case_id: case_id,
          filename: filename,
          content_type: content_type,
          storage_path: storage_path
        },
        attrs
      )
    )
  end

  def generate_letter_draft(%Case{} = case) do
    case = Repo.preload(case, [:legal_entity, :evidence_attachments], force: true)
    violations = list_violation_communications(case.id)
    attachments = list_case_attachments(case.id)
    profile = get_claimant_profile()

    draft =
      LetterDraft.render(case, violations, attachments, claimant_profile: profile)

    with {:ok, case} <- update_case(case, %{letter_draft: draft}) do
      maybe_advance_workflow(case, "draft_review")
    end
  end

  def save_letter_draft(%Case{} = case, body) do
    letter_draft = if String.trim(body || "") == "", do: nil, else: body

    with {:ok, case} <- update_case(case, %{letter_draft: letter_draft}) do
      if letter_draft do
        maybe_advance_workflow(case, "draft_review")
      else
        {:ok, case}
      end
    end
  end

  def generate_court_filing_draft(%Case{} = case) do
    case = Repo.preload(case, [:legal_entity, :evidence_attachments], force: true)
    violations = list_violation_communications(case.id)

    if violations == [] do
      {:error, :no_violations}
    else
      attachments = list_case_attachments(case.id)
      profile = get_claimant_profile()

      limits = assess_case_filing_limits(case)

      draft =
        CourtFilingDraft.render(case, violations, attachments,
          claimant_profile: profile,
          filing_limits: limits
        )

      update_case(case, %{court_filing_draft: draft})
    end
  end

  def generate_civil_complaint_draft(%Case{} = case) do
    case = Repo.preload(case, [:legal_entity, :evidence_attachments], force: true)
    violations = list_violation_communications(case.id)

    if violations == [] do
      {:error, :no_violations}
    else
      attachments = list_case_attachments(case.id)
      profile = get_claimant_profile()
      limits = assess_case_filing_limits(case)

      draft =
        CivilComplaintDraft.render(case, violations, attachments,
          claimant_profile: profile,
          filing_limits:
            FilingLimits.civil_assess(length(violations),
              calendar_year: limits.calendar_year,
              high_small_claims_filings_this_year: limits.small_claims_high_filings_this_year
            )
        )

      update_case(case, %{civil_complaint_draft: draft})
    end
  end

  def assess_case_filing_limits(%Case{} = case) do
    violations = list_violation_communications(case.id)
    year = Date.utc_today().year

    FilingLimits.assess(length(violations),
      calendar_year: year,
      high_small_claims_filings_this_year:
        count_high_small_claims_filings(year, exclude_case_id: case.id)
    )
  end

  def count_high_small_claims_filings(year, opts \\ []) do
    exclude_id = Keyword.get(opts, :exclude_case_id)
    {start_date, end_date} = year_date_range(year)

    query =
      from c in Case,
        where: not is_nil(c.court_filed_at),
        where: c.court_filed_at >= ^start_date and c.court_filed_at <= ^end_date,
        where: c.court_filed_venue == "small_claims",
        where: c.court_filed_amount > ^FilingLimits.small_claims_high_threshold()

    query =
      if exclude_id do
        from c in query, where: c.id != ^exclude_id
      else
        query
      end

    Repo.aggregate(query, :count)
  end

  def record_court_filing(%Case{} = case, attrs) when is_map(attrs) do
    case
    |> Case.court_filing_changeset(attrs)
    |> Repo.update()
  end

  def change_court_filing(%Case{} = case, attrs \\ %{}) do
    Case.court_filing_changeset(case, attrs)
  end

  def advance_case_workflow(%Case{} = case) do
    case = Repo.preload(case, [:legal_entity, :evidence_attachments], force: true)
    violations = list_violation_communications(case.id)
    attachments = list_case_attachments(case.id)
    filing_limits = assess_case_filing_limits(case)

    with :ok <-
           Workflow.validate_advance(case, violations, attachments, filing_limits: filing_limits),
         next_step <- Workflow.next_step(case.workflow_step),
         next_status <- Workflow.next_status(next_step) do
      update_case(case, %{workflow_step: next_step, status: next_status})
    end
  end

  def settle_case(%Case{} = case) do
    update_case(case, %{workflow_step: "settled", status: Workflow.next_status("settled")})
  end

  def workflow_requirements(%Case{} = case) do
    case = Repo.preload(case, [:legal_entity], force: true)
    violations = list_violation_communications(case.id)
    attachments = list_case_attachments(case.id)
    filing_limits = assess_case_filing_limits(case)

    base_requirements(case, violations, attachments) ++
      litigation_requirements(case, filing_limits)
  end

  defp base_requirements(case, violations, attachments) do
    [
      %{
        label: "Violations marked",
        met: violations != [],
        detail: "#{length(violations)} violation(s)"
      },
      %{
        label: "Legal entity address",
        met: legal_entity_mailable?(case.legal_entity),
        detail: "Required for certified mail"
      },
      %{
        label: "Evidence attachments",
        met: attachments != [],
        detail: "#{length(attachments)} file(s)"
      },
      %{
        label: "Letter draft",
        met: case.letter_draft not in [nil, ""],
        detail: "Generate before sending"
      }
    ]
  end

  defp litigation_requirements(case, filing_limits) do
    if case.workflow_step in [
         "intake",
         "triage",
         "evidence_review",
         "draft_review",
         "ready_to_send",
         "settled"
       ] do
      []
    else
      draft_label =
        case filing_limits.recommended_venue do
          "small_claims" -> "Small claims filing draft"
          _ -> "Civil complaint draft"
        end

      draft_met =
        case filing_limits.recommended_venue do
          "small_claims" -> case.court_filing_draft not in [nil, ""]
          _ -> case.civil_complaint_draft not in [nil, ""]
        end

      [
        %{
          label: "Filing venue",
          met: true,
          detail:
            "#{filing_limits.recommended_venue_label} (#{format_money(filing_limits.total_damages)} total damages)"
        },
        %{
          label: draft_label,
          met: draft_met,
          detail: "Required before ready to file"
        },
        %{
          label: "Court filing recorded",
          met: case.court_filed_at != nil,
          detail: court_filing_detail(case)
        }
      ]
    end
  end

  defp court_filing_detail(%Case{court_filed_at: nil}),
    do: "Record date, venue, and amount after filing"

  defp court_filing_detail(%Case{} = case) do
    venue = FilingLimits.venue_label(case.court_filed_venue || "")
    amount = format_money(case.court_filed_amount)
    "Filed #{case.court_filed_at} — #{venue}, #{amount}"
  end

  defp format_money(nil), do: "—"

  defp format_money(%Decimal{} = amount) do
    amount
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
    |> then(&"$#{&1}")
  end

  defp year_date_range(year) do
    {Date.new!(year, 1, 1), Date.new!(year, 12, 31)}
  end

  defp legal_entity_mailable?(%LegalEntity{} = entity), do: LegalEntity.mailable?(entity)
  defp legal_entity_mailable?(_), do: false

  def get_claimant_profile do
    case Repo.one(ClaimantProfile) do
      nil -> %ClaimantProfile{}
      profile -> profile
    end
  end

  def change_claimant_profile(%ClaimantProfile{} = profile, attrs \\ %{}) do
    ClaimantProfile.changeset(profile, attrs)
  end

  def update_claimant_profile(attrs) when is_map(attrs) do
    profile = get_or_insert_claimant_profile!()

    profile
    |> ClaimantProfile.changeset(attrs)
    |> Repo.update()
  end

  def import_claimant_from_me_card(opts \\ []) do
    case MeCard.read(opts) do
      {:ok, card} ->
        attrs =
          card
          |> Map.take([:name, :address, :phone, :email])
          |> Enum.map(fn {key, value} -> {key, value} end)
          |> Enum.into(%{})

        update_claimant_profile(attrs)

      other ->
        other
    end
  end

  defp get_or_insert_claimant_profile! do
    case Repo.one(ClaimantProfile) do
      nil ->
        {:ok, profile} = Repo.insert(%ClaimantProfile{})
        profile

      profile ->
        profile
    end
  end

  @terminal_mail_statuses ~w(delivered returned)

  def update_mail_tracking(%Case{} = case, attrs) when is_map(attrs) do
    case
    |> Case.mail_tracking_changeset(attrs)
    |> Repo.update()
  end

  def save_mail_tracking_number(%Case{} = case, raw_number) do
    normalized = UspsTracking.normalize_tracking_number(raw_number)

    attrs =
      if normalized do
        %{
          mail_tracking_number: normalized,
          mail_delivery_status: "pending",
          mail_tracking_summary: nil,
          mail_tracking_checked_at: nil
        }
      else
        %{
          mail_tracking_number: nil,
          mail_delivery_status: nil,
          mail_tracking_summary: nil,
          mail_tracking_checked_at: nil
        }
      end

    update_mail_tracking(case, attrs)
  end

  def refresh_mail_tracking(%Case{} = case, opts \\ []) do
    on_step = Keyword.get(opts, :on_step, fn _ -> :ok end)
    number = case.mail_tracking_number

    cond do
      number in [nil, ""] ->
        UspsTracking.emit_progress(
          on_step,
          :validate,
          :error,
          UspsTracking.error_message(:no_tracking_number)
        )

        {:error, :no_tracking_number}

      true ->
        case UspsTracking.lookup(number, on_step: on_step) do
          {:ok, result} ->
            save_mail_tracking_result(case, result, on_step)

          {:error, _} = error ->
            error
        end
    end
  end

  defp apply_consumed_helper_page(case_id, params) do
    with {:ok, parsed} <- UspsTracking.parse_helper_payload(params),
         %Case{} = case_record <- Repo.get(Case, case_id),
         {:ok, case_record} <-
           save_mail_tracking_result(
             case_record,
             Map.put(parsed, :checked_at, DateTime.utc_now() |> DateTime.truncate(:second)),
             fn _ -> :ok end
           ) do
      {:ok, case_record}
    else
      nil ->
        {:error, {:helper_failed, case_id, :case_not_found}}

      {:error, reason} ->
        {:error, {:helper_failed, case_id, reason}}
    end
  end

  defp save_mail_tracking_result(case, result, on_step) do
    UspsTracking.emit_progress(
      on_step,
      :save,
      :running,
      "Writing #{result.delivery_status} to this case"
    )

    with {:ok, case} <-
           update_mail_tracking(case, %{
             mail_delivery_status: result.delivery_status,
             mail_tracking_summary: result.summary,
             mail_tracking_checked_at: result.checked_at
           }),
         {:ok, case} <- maybe_mark_delivered_workflow(case) do
      UspsTracking.emit_progress(on_step, :save, :ok, save_progress_detail(case, result))
      {:ok, case}
    else
      {:error, reason} = error ->
        UspsTracking.emit_progress(on_step, :save, :error, UspsTracking.error_message(reason))
        error
    end
  end

  defp save_progress_detail(
         %Case{workflow_step: "delivered", mail_delivery_status: "delivered"},
         result
       ) do
    "#{result.summary} Workflow moved to delivered."
  end

  defp save_progress_detail(_case, result), do: result.summary

  defp maybe_mark_delivered_workflow(%Case{mail_delivery_status: "delivered"} = case) do
    maybe_advance_workflow(case, "delivered")
  end

  defp maybe_mark_delivered_workflow(case), do: {:ok, case}

  defp maybe_advance_workflow(%Case{} = case, target_step) do
    if Workflow.before?(case.workflow_step, target_step) do
      update_case(case, %{
        workflow_step: target_step,
        status: Workflow.next_status(target_step)
      })
    else
      {:ok, case}
    end
  end

  def refresh_all_mail_tracking do
    cases =
      from(c in Case,
        where: not is_nil(c.mail_tracking_number) and c.mail_tracking_number != "",
        where:
          c.mail_delivery_status not in @terminal_mail_statuses or is_nil(c.mail_delivery_status)
      )
      |> Repo.all()

    Enum.reduce(cases, %{checked: 0, updated: 0, errors: 0}, fn case_record, acc ->
      acc = %{acc | checked: acc.checked + 1}

      case refresh_mail_tracking(case_record) do
        {:ok, _} ->
          %{acc | updated: acc.updated + 1}

        {:error, reason} ->
          Logger.warning(
            "[PeriodicTrackingRefresh] case=#{case_record.id} #{UspsTracking.error_message(reason)}"
          )

          %{acc | errors: acc.errors + 1}
      end
    end)
  end

  def apply_usps_helper_page(params) when is_map(params) do
    number =
      UspsTracking.normalize_tracking_number(
        params["tracking_number"] || params[:tracking_number]
      )

    case number do
      nil ->
        {:error, :not_pending}

      number ->
        case UspsBrowserHelper.take(number) do
          {:ok, %{case_id: case_id}} ->
            apply_consumed_helper_page(case_id, params)

          {:error, :not_pending} ->
            {:error, :not_pending}
        end
    end
  end

  def chrome_extension_dir, do: UspsBrowserHelper.extension_dir()

  def usps_tracking_configured?, do: UspsTracking.configured?()
  def mail_tracking_url(number), do: UspsTracking.tracking_url(number)

  def list_linked_cases(%Case{} = case_record), do: CaseGroups.list_linked_cases(case_record)

  def link_cases(%Case{} = case_a, %Case{} = case_b), do: CaseGroups.link_cases(case_a, case_b)

  def unlink_case(%Case{} = case_record), do: CaseGroups.unlink_case(case_record)

  def merge_case_into(%Case{} = target, source_id),
    do: CaseGroups.merge_case_into(target, source_id)

  def list_linkable_cases(%Case{} = case_record) do
    search_linkable_cases(case_record, "")
  end

  @doc """
  Finds cases that can be linked to `case_record`, matching company name,
  notes, case id, or sender phone number.
  """
  def search_linkable_cases(%Case{} = case_record, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 8)
    trimmed = query |> to_string() |> String.trim()

    if trimmed == "" do
      []
    else
      exclude_ids = linkable_exclude_ids(case_record)

      Case
      |> where([c], c.id not in ^exclude_ids)
      |> SearchFilter.apply_case_search(trimmed)
      |> order_by([c], desc: c.inserted_at)
      |> limit(^limit)
      |> preload(:legal_entity)
      |> Repo.all()
    end
  end

  defp linkable_exclude_ids(%Case{} = case_record) do
    linked_ids =
      case_record
      |> CaseGroups.list_linked_cases()
      |> Enum.map(& &1.id)

    [case_record.id | linked_ids]
  end
end

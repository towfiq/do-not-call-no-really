defmodule DncWatchdog.Enforcement do
  @moduledoc """
  The Enforcement context.
  """

  import Ecto.Query, warn: false
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
  alias DncWatchdog.Enforcement.Local.MeCard
  alias DncWatchdog.Enforcement.UspsTracking
  alias DncWatchdog.Enforcement.CaseGroups
  alias DncWatchdog.Enforcement.Workflow

  def list_cases(opts \\ []) do
    Case
    |> order_by([c], desc: c.inserted_at)
    |> maybe_preload_communications(opts)
    |> maybe_preload_legal_entity(opts)
    |> Repo.all()
  end

  defp maybe_preload_communications(query, preload_communications: true) do
    preload(query, :communications)
  end

  defp maybe_preload_communications(query, _opts), do: query

  defp maybe_preload_legal_entity(query, preload_legal_entity: true) do
    preload(query, :legal_entity)
  end

  defp maybe_preload_legal_entity(query, _opts), do: query

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
    |> Repo.all()
  end

  def list_communications(opts \\ []) do
    opts
    |> Keyword.put_new(:limit, 1_000)
    |> communications_query()
    |> preload(:case)
    |> Repo.all()
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
  end

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

  def count_communications(opts \\ []) do
    Communication
    |> apply_communication_filters(opts)
    |> Repo.aggregate(:count, :id)
  end

  def get_communication!(id), do: Repo.get!(Communication, id)

  def get_communication_by_fingerprint(fingerprint) do
    Repo.get_by(Communication, source_fingerprint: fingerprint)
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
        attrs = %{peer_type: Atom.to_string(peer_type), peer_key: peer_key, display_peer: display_peer}

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

  defp peer_query(peer) do
    if ContactFilter.email_peer?(peer) do
      email = String.downcase(peer)

      from c in Communication,
        where:
          (c.direction == "incoming" and fragment("lower(?)", c.from_number) == ^email) or
            (c.direction == "outgoing" and fragment("lower(?)", c.to_number) == ^email)
    else
      normalized = Phone.normalize(peer)

      from c in Communication,
        where:
          (c.direction == "incoming" and c.from_number == ^normalized) or
            (c.direction == "outgoing" and c.to_number == ^normalized)
    end
  end

  def list_violation_communications(case_id) do
    list_case_communications(case_id, hide_excluded: true, violations_only: true)
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
      LetterDraft.render(case, violations, attachments,
        claimant_profile: profile
      )

    update_case(case, %{letter_draft: draft})
  end

  def advance_case_workflow(%Case{} = case) do
    case = Repo.preload(case, [:legal_entity, :evidence_attachments], force: true)
    violations = list_violation_communications(case.id)
    attachments = list_case_attachments(case.id)

    with :ok <- Workflow.validate_advance(case, violations, attachments),
         next_step <- Workflow.next_step(case.workflow_step),
         next_status <- Workflow.next_status(next_step) do
      update_case(case, %{workflow_step: next_step, status: next_status})
    end
  end

  def workflow_requirements(%Case{} = case) do
    case = Repo.preload(case, [:legal_entity], force: true)
    violations = list_violation_communications(case.id)
    attachments = list_case_attachments(case.id)

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

  def refresh_mail_tracking(%Case{} = case) do
    number = case.mail_tracking_number

    cond do
      number in [nil, ""] ->
        {:error, :no_tracking_number}

      true ->
        case UspsTracking.lookup(number) do
          {:ok, result} ->
            update_mail_tracking(case, %{
              mail_delivery_status: result.delivery_status,
              mail_tracking_summary: result.summary,
              mail_tracking_checked_at: result.checked_at
            })

          {:error, _} = error ->
            error
        end
    end
  end

  def refresh_all_mail_tracking do
    cases =
      from(c in Case,
        where: not is_nil(c.mail_tracking_number) and c.mail_tracking_number != "",
        where: c.mail_delivery_status not in @terminal_mail_statuses or is_nil(c.mail_delivery_status)
      )
      |> Repo.all()

    Enum.reduce(cases, %{checked: 0, updated: 0, errors: 0}, fn case_record, acc ->
      acc = %{acc | checked: acc.checked + 1}

      case refresh_mail_tracking(case_record) do
        {:ok, _} -> %{acc | updated: acc.updated + 1}
        {:error, _} -> %{acc | errors: acc.errors + 1}
      end
    end)
  end

  def usps_tracking_configured?, do: UspsTracking.configured?()
  def mail_tracking_url(number), do: UspsTracking.tracking_url(number)

  def list_linked_cases(%Case{} = case_record), do: CaseGroups.list_linked_cases(case_record)

  def link_cases(%Case{} = case_a, %Case{} = case_b), do: CaseGroups.link_cases(case_a, case_b)

  def unlink_case(%Case{} = case_record), do: CaseGroups.unlink_case(case_record)

  def merge_case_into(%Case{} = target, source_id), do: CaseGroups.merge_case_into(target, source_id)

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
      needle = String.downcase(trimmed)
      phone_case_ids = phone_matching_case_ids(trimmed)

      name_match =
        dynamic([c], fragment("instr(lower(?), ?) > 0", c.company_name, ^needle))

      notes_match =
        dynamic([c], fragment("instr(lower(?), ?) > 0", coalesce(c.notes, ""), ^needle))

      phone_match =
        if phone_case_ids == [] do
          dynamic(false)
        else
          dynamic([c], c.id in ^phone_case_ids)
        end

      id_match =
        case Integer.parse(trimmed) do
          {id, ""} -> dynamic([c], c.id == ^id)
          _ -> dynamic(false)
        end

      Case
      |> where([c], c.id not in ^exclude_ids)
      |> where(^dynamic([c], ^name_match or ^notes_match or ^phone_match or ^id_match))
      |> order_by([c], desc: c.inserted_at)
      |> limit(^limit)
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

  defp phone_matching_case_ids(query) do
    digits =
      query
      |> to_string()
      |> String.replace(~r/[^0-9]/, "")

    if digits == "" do
      []
    else
      like = "%#{digits}%"

      Communication
      |> where(
        [comm],
        comm.direction == "incoming" and like(comm.from_number, ^like)
      )
      |> group_by([comm], comm.case_id)
      |> select([comm], comm.case_id)
      |> Repo.all()
    end
  end
end

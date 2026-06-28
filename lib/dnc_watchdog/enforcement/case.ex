defmodule DncWatchdog.Enforcement.Case do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(new investigating drafting_letter sent closed)
  @workflow_steps ~w(intake triage evidence_review draft_review ready_to_send sent archived)
  @mail_delivery_statuses ~w(pending pre_shipment in_transit out_for_delivery delivered returned alert unknown)

  alias DncWatchdog.Enforcement.CaseGroup

  schema "cases" do
    field :status, :string
    field :company_name, :string
    field :workflow_step, :string
    field :notes, :string
    field :letter_draft, :string
    field :claimant_name, :string
    field :claimant_address, :string
    field :claimant_phone, :string
    field :claimant_email, :string
    field :dnc_registration_date, :date
    field :stop_contact_date, :date
    field :relief_amount_per_violation, :decimal
    field :settlement_amount, :decimal
    field :small_claims_county, :string
    field :mail_tracking_number, :string
    field :mail_delivery_status, :string
    field :mail_tracking_summary, :string
    field :mail_tracking_checked_at, :utc_datetime

    belongs_to :legal_entity, DncWatchdog.Enforcement.LegalEntity
    belongs_to :case_group, CaseGroup
    has_many :communications, DncWatchdog.Enforcement.Communication
    has_many :evidence_attachments, DncWatchdog.Enforcement.EvidenceAttachment

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(case, attrs) do
    case
    |> cast(attrs, [
      :company_name,
      :status,
      :workflow_step,
      :notes,
      :letter_draft,
      :claimant_name,
      :claimant_address,
      :claimant_phone,
      :claimant_email,
      :dnc_registration_date,
      :stop_contact_date,
      :relief_amount_per_violation,
      :settlement_amount,
      :small_claims_county,
      :legal_entity_id,
      :case_group_id
    ])
    |> validate_required([:company_name, :status, :workflow_step])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:workflow_step, @workflow_steps)
  end

  @doc false
  def mail_tracking_changeset(case, attrs) do
    case
    |> cast(attrs, [
      :mail_tracking_number,
      :mail_delivery_status,
      :mail_tracking_summary,
      :mail_tracking_checked_at
    ])
    |> validate_mail_tracking_number()
    |> validate_inclusion(:mail_delivery_status, @mail_delivery_statuses)
  end

  defp validate_mail_tracking_number(changeset) do
    case get_change(changeset, :mail_tracking_number) do
      nil ->
        changeset

      "" ->
        put_change(changeset, :mail_tracking_number, nil)

      number when is_binary(number) ->
        normalized =
          number
          |> String.trim()
          |> String.replace(~r/[^0-9A-Za-z]/, "")

        if normalized == "" do
          add_error(changeset, :mail_tracking_number, "must contain a valid tracking number")
        else
          put_change(changeset, :mail_tracking_number, normalized)
        end
    end
  end

  def mail_delivery_statuses, do: @mail_delivery_statuses
end

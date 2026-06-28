defmodule DncWatchdog.Repo.Migrations.AddEnforcementWorkflowFeatures do
  use Ecto.Migration

  def change do
    create table(:legal_entities) do
      add :legal_name, :string, null: false
      add :entity_type, :string, null: false, default: "company"
      add :street, :string
      add :city, :string
      add :state, :string
      add :zip, :string
      add :attn, :string
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    alter table(:cases) do
      add :legal_entity_id, references(:legal_entities, on_delete: :nilify_all)
      add :claimant_name, :string
      add :claimant_phone, :string
      add :dnc_registration_date, :date
      add :relief_amount_per_violation, :decimal, precision: 10, scale: 2
    end

    alter table(:communications) do
      add :violation_status, :string, null: false, default: "pending"
    end

    create table(:evidence_attachments) do
      add :case_id, references(:cases, on_delete: :delete_all), null: false
      add :communication_id, references(:communications, on_delete: :nilify_all)
      add :filename, :string, null: false
      add :content_type, :string
      add :storage_path, :string, null: false
      add :caption, :string

      timestamps(type: :utc_datetime)
    end

    create index(:communications, [:violation_status])
    create index(:evidence_attachments, [:case_id])
    create index(:cases, [:legal_entity_id])
  end
end

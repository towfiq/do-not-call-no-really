defmodule DncWatchdog.Repo.Migrations.AddCivilComplaintAndCourtFilingFields do
  use Ecto.Migration

  def change do
    alter table(:cases) do
      add :civil_complaint_draft, :text
      add :court_filed_at, :date
      add :court_filed_venue, :string
      add :court_filed_amount, :decimal, precision: 10, scale: 2
    end

    create index(:cases, [:court_filed_at])
  end
end

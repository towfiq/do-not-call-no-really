defmodule DncWatchdog.Repo.Migrations.CreateCases do
  use Ecto.Migration

  def change do
    create table(:cases) do
      add :company_name, :string
      add :status, :string
      add :workflow_step, :string
      add :notes, :text
      add :letter_draft, :text

      timestamps(type: :utc_datetime)
    end
  end
end

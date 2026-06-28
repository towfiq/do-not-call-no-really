defmodule DncWatchdog.Repo.Migrations.CreateCommunications do
  use Ecto.Migration

  def change do
    create table(:communications) do
      add :timestamp, :naive_datetime, null: false
      add :channel, :string, null: false
      add :direction, :string, null: false
      add :from_number, :string, null: false
      add :to_number, :string, null: false
      add :duration_seconds, :integer, default: 0, null: false
      add :body, :text
      add :company, :string
      add :reasons, :text
      add :case_id, references(:cases, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:communications, [:case_id])
    create index(:communications, [:from_number])
    create index(:communications, [:company])
  end
end


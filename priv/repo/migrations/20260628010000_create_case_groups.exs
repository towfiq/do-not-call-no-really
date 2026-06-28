defmodule DncWatchdog.Repo.Migrations.CreateCaseGroups do
  use Ecto.Migration

  def change do
    create table(:case_groups) do
      add :name, :string

      timestamps(type: :utc_datetime)
    end

    alter table(:cases) do
      add :case_group_id, references(:case_groups, on_delete: :nilify_all)
    end

    create index(:cases, [:case_group_id])
  end
end

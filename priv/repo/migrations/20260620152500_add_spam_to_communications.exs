defmodule DncWatchdog.Repo.Migrations.AddSpamToCommunications do
  use Ecto.Migration

  def change do
    alter table(:communications) do
      add :spam, :boolean, default: false, null: false
    end

    create index(:communications, [:spam])
  end
end

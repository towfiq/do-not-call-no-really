defmodule DncWatchdog.Repo.Migrations.AddCommunicationsSourceFingerprint do
  use Ecto.Migration

  def change do
    alter table(:communications) do
      add :source_fingerprint, :string
    end

    create unique_index(:communications, [:source_fingerprint],
             where: "source_fingerprint IS NOT NULL"
           )
  end
end

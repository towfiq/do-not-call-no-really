defmodule DncWatchdog.Repo.Migrations.AddLegalEntityCountry do
  use Ecto.Migration

  def change do
    alter table(:legal_entities) do
      add :country, :string, default: "US"
    end
  end
end

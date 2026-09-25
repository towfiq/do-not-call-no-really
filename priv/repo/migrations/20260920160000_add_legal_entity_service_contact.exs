defmodule DncWatchdog.Repo.Migrations.AddLegalEntityServiceContact do
  use Ecto.Migration

  def change do
    alter table(:legal_entities) do
      add :phone, :string
      add :agent_name, :string
      add :agent_title, :string
      add :agent_street, :string
      add :agent_city, :string
      add :agent_state, :string
      add :agent_zip, :string
      add :agent_phone, :string
      add :sos_entity_number, :string
      add :sos_url, :string
    end
  end
end

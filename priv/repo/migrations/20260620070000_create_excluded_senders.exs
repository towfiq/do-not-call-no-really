defmodule DncWatchdog.Repo.Migrations.CreateExcludedSenders do
  use Ecto.Migration

  def change do
    create table(:excluded_senders) do
      add :peer_key, :string, null: false
      add :peer_type, :string, null: false
      add :display_peer, :string, null: false
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:excluded_senders, [:peer_key])
  end
end

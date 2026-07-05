defmodule DncWatchdog.Repo.Migrations.CreateLocalImportSync do
  use Ecto.Migration

  def change do
    create table(:local_import_sync) do
      add :last_synced_at, :utc_datetime
      add :last_started_at, :utc_datetime
      add :last_status, :string
      add :last_error, :text
      add :last_message_rows, :integer
      add :last_call_rows, :integer
      add :last_created_communications, :integer, default: 0
      add :last_skipped_duplicates, :integer, default: 0

      timestamps(type: :utc_datetime)
    end
  end
end

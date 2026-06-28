defmodule DncWatchdog.Repo.Migrations.AddMailTrackingToCases do
  use Ecto.Migration

  def change do
    alter table(:cases) do
      add :mail_tracking_number, :string
      add :mail_delivery_status, :string
      add :mail_tracking_summary, :text
      add :mail_tracking_checked_at, :utc_datetime
    end

    create index(:cases, [:mail_delivery_status])
  end
end

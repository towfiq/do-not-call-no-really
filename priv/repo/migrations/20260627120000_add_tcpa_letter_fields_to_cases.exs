defmodule DncWatchdog.Repo.Migrations.AddTcpaLetterFieldsToCases do
  use Ecto.Migration

  def change do
    alter table(:cases) do
      add :claimant_address, :text
      add :claimant_email, :string
      add :stop_contact_date, :date
      add :settlement_amount, :decimal, precision: 10, scale: 2
      add :small_claims_county, :string
    end
  end
end

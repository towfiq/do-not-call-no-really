defmodule DncWatchdog.Repo.Migrations.CreateClaimantProfiles do
  use Ecto.Migration

  def change do
    create table(:claimant_profiles) do
      add :name, :string
      add :address, :text
      add :phone, :string
      add :email, :string
      add :dnc_registration_date, :date
      add :small_claims_county, :string

      timestamps(type: :utc_datetime)
    end
  end
end

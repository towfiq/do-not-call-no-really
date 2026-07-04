defmodule DncWatchdog.Repo.Migrations.AddCourtFilingDraftToCases do
  use Ecto.Migration

  def change do
    alter table(:cases) do
      add :court_filing_draft, :text
    end
  end
end

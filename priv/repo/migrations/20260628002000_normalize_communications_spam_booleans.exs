defmodule DncWatchdog.Repo.Migrations.NormalizeCommunicationsSpamBooleans do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE communications
    SET spam = CASE
      WHEN spam IN ('true', 'TRUE', '1', 1) THEN 1
      ELSE 0
    END
    """)
  end

  def down do
    execute("""
    UPDATE communications
    SET spam = CASE
      WHEN spam IN (1, '1') THEN 'true'
      ELSE 'false'
    END
    """)
  end
end

defmodule DncWatchdog.Repo.Migrations.UnwindOwnNumberCaseAssignments do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    DncWatchdog.Enforcement.unwind_own_number_case_assignments()
  end

  def down do
    :ok
  end
end

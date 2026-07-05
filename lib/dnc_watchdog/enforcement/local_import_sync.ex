defmodule DncWatchdog.Enforcement.LocalImportSync do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "local_import_sync" do
    field :last_synced_at, :utc_datetime
    field :last_started_at, :utc_datetime
    field :last_status, :string
    field :last_error, :string
    field :last_message_rows, :integer
    field :last_call_rows, :integer
    field :last_created_communications, :integer, default: 0
    field :last_skipped_duplicates, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @statuses ~w(ok error)

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :last_synced_at,
      :last_started_at,
      :last_status,
      :last_error,
      :last_message_rows,
      :last_call_rows,
      :last_created_communications,
      :last_skipped_duplicates
    ])
    |> validate_inclusion(:last_status, @statuses)
  end
end

defmodule DncWatchdog.Enforcement.EvidenceAttachment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "evidence_attachments" do
    field :filename, :string
    field :content_type, :string
    field :storage_path, :string
    field :caption, :string

    belongs_to :case, DncWatchdog.Enforcement.Case
    belongs_to :communication, DncWatchdog.Enforcement.Communication

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:filename, :content_type, :storage_path, :caption, :case_id, :communication_id])
    |> validate_required([:filename, :storage_path, :case_id])
  end
end

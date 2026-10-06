defmodule DncWatchdog.Enforcement.EvidenceAttachment do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          filename: String.t() | nil,
          content_type: String.t() | nil,
          storage_path: String.t() | nil,
          caption: String.t() | nil,
          case_id: integer() | nil,
          communication_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

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
    |> cast(attrs, [
      :filename,
      :content_type,
      :storage_path,
      :caption,
      :case_id,
      :communication_id
    ])
    |> validate_required([:filename, :storage_path, :case_id])
  end
end

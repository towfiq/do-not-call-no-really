defmodule DncWatchdog.Enforcement.LegalEntity do
  use Ecto.Schema
  import Ecto.Changeset

  schema "legal_entities" do
    field :legal_name, :string
    field :entity_type, :string, default: "company"
    field :street, :string
    field :city, :string
    field :state, :string
    field :zip, :string
    field :attn, :string
    field :notes, :string

    has_many :cases, DncWatchdog.Enforcement.Case

    timestamps(type: :utc_datetime)
  end

  @entity_types ~w(company individual unknown)

  @doc false
  def changeset(legal_entity, attrs) do
    legal_entity
    |> cast(attrs, [:legal_name, :entity_type, :street, :city, :state, :zip, :attn, :notes])
    |> validate_required([:legal_name])
    |> validate_inclusion(:entity_type, @entity_types)
  end

  @doc """
  True when enough address fields exist to mail a demand letter.
  """
  def mailable?(%__MODULE__{} = entity) do
    entity.street not in [nil, ""] and
      entity.city not in [nil, ""] and
      entity.state not in [nil, ""] and
      entity.zip not in [nil, ""]
  end

  def formatted_address(%__MODULE__{} = entity) do
    lines =
      [
        entity.street,
        [entity.city, entity.state, entity.zip] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(", ")
      ]
      |> Enum.reject(&(&1 in [nil, ""]))

    Enum.join(lines, "\n")
  end
end

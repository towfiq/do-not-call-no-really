defmodule DncWatchdog.Enforcement.CaseGroup do
  use Ecto.Schema
  import Ecto.Changeset

  alias DncWatchdog.Enforcement.Case

  schema "case_groups" do
    field :name, :string

    has_many :cases, Case

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(case_group, attrs) do
    case_group
    |> cast(attrs, [:name])
  end
end

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
    field :country, :string, default: "US"
    field :phone, :string
    field :attn, :string
    field :agent_name, :string
    field :agent_title, :string
    field :agent_street, :string
    field :agent_city, :string
    field :agent_state, :string
    field :agent_zip, :string
    field :agent_phone, :string
    field :sos_entity_number, :string
    field :sos_url, :string
    field :notes, :string

    has_many :cases, DncWatchdog.Enforcement.Case

    timestamps(type: :utc_datetime)
  end

  @entity_types ~w(company individual unknown)

  @doc false
  def changeset(legal_entity, attrs) do
    legal_entity
    |> cast(attrs, [
      :legal_name,
      :entity_type,
      :street,
      :city,
      :state,
      :zip,
      :country,
      :phone,
      :attn,
      :agent_name,
      :agent_title,
      :agent_street,
      :agent_city,
      :agent_state,
      :agent_zip,
      :agent_phone,
      :sos_entity_number,
      :sos_url,
      :notes
    ])
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
    Enum.join(address_lines(entity), "\n")
  end

  @doc """
  Mailing lines including country when the entity is not in the United States.
  """
  def address_lines(%__MODULE__{} = entity) do
    locality =
      [entity.city, entity.state, entity.zip]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(", ")

    [entity.street, locality, foreign_country_line(entity)]
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  def country_label(%__MODULE__{} = entity), do: country_label(entity.country)
  def country_label(nil), do: "United States"
  def country_label(""), do: "United States"

  def country_label(country) when is_binary(country) do
    case normalize_country(country) do
      "US" -> "United States"
      "GB" -> "United Kingdom"
      other -> other
    end
  end

  def us?(%__MODULE__{country: country}), do: us_country?(country)
  def us?(country) when is_binary(country) or is_nil(country), do: us_country?(country)
  def us?(_), do: true

  def normalize_country(nil), do: "US"
  def normalize_country(""), do: "US"

  def normalize_country(country) when is_binary(country) do
    case country |> String.trim() |> String.upcase() do
      value when value in ["US", "USA", "UNITED STATES", "UNITED STATES OF AMERICA"] ->
        "US"

      value when value in ["GB", "UK", "ENG", "ENGLAND", "UNITED KINGDOM", "GREAT BRITAIN"] ->
        "GB"

      _ ->
        String.trim(country)
    end
  end

  defp us_country?(country), do: normalize_country(country) == "US"

  defp foreign_country_line(entity) do
    if us?(entity), do: nil, else: country_label(entity)
  end

  @doc """
  Person or agent authorized to accept service of process (SC-100 item 2).
  """
  def service_agent(%__MODULE__{} = entity) do
    name = present(entity.agent_name) || present(entity.attn)

    if name do
      address_lines =
        [
          present(entity.agent_street) || present(entity.street),
          [
            present(entity.agent_city) || present(entity.city),
            present(entity.agent_state) || present(entity.state),
            present(entity.agent_zip) || present(entity.zip)
          ]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(", "),
          unless(us?(entity), do: country_label(entity))
        ]
        |> Enum.reject(&(&1 in [nil, ""]))

      %{
        name: name,
        title: present(entity.agent_title) || "Registered Agent",
        phone: present(entity.agent_phone) || present(entity.phone),
        street: present(entity.agent_street) || present(entity.street),
        city: present(entity.agent_city) || present(entity.city),
        state: present(entity.agent_state) || present(entity.state),
        zip: present(entity.agent_zip) || present(entity.zip),
        country: unless(us?(entity), do: country_label(entity)),
        address: Enum.join(address_lines, "\n")
      }
    end
  end

  def service_agent(_), do: nil

  defp present(value) when value in [nil, ""], do: nil
  defp present(value) when is_binary(value), do: String.trim(value)
  defp present(value), do: value
end

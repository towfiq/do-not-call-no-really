defmodule DncWatchdog.Enforcement.ClaimantProfile do
  @moduledoc """
  Singleton profile for the claimant's contact details used in demand letters.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "claimant_profiles" do
    field :name, :string
    field :address, :string
    field :phone, :string
    field :email, :string
    field :dnc_registration_date, :date
    field :small_claims_county, :string

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{
          name: String.t() | nil,
          address: String.t() | nil,
          phone: String.t() | nil,
          email: String.t() | nil,
          dnc_registration_date: Date.t() | nil,
          small_claims_county: String.t() | nil
        }

  @fields [:name, :address, :phone, :email, :dnc_registration_date, :small_claims_county]

  @doc false
  def changeset(profile, attrs) do
    profile
    |> cast(attrs, @fields)
  end

  @doc """
  Resolves a claimant field from explicit opts, case value, saved profile, and env vars.
  """
  @spec resolve(atom(), term(), term(), t() | nil) :: term()
  def resolve(field, opt_value, case_value, profile \\ nil) do
    profile = profile || empty()

    [opt_value, case_value, Map.get(profile, field), env_value(field)]
    |> Enum.find_value(&present/1)
    |> case do
      nil -> default_placeholder(field)
      value -> value
    end
  end

  @doc """
  Returns keyword list defaults for letter rendering.
  """
  @spec letter_opts(t() | nil) :: keyword()
  def letter_opts(profile \\ nil) do
    profile = profile || empty()

    [
      claimant_name: resolve(:name, nil, nil, profile),
      claimant_address: resolve(:address, nil, nil, profile),
      claimant_phone: resolve(:phone, nil, nil, profile),
      claimant_email: resolve(:email, nil, nil, profile),
      dnc_registration_date: resolve_dnc_date(nil, nil, profile),
      small_claims_county: resolve(:small_claims_county, nil, nil, profile)
    ]
  end

  defp resolve_dnc_date(opt_value, case_value, profile) do
    [opt_value, case_value, profile.dnc_registration_date]
    |> Enum.find_value(&present/1)
  end

  defp env_value(:name), do: System.get_env("DNC_MY_NAME")
  defp env_value(:address), do: System.get_env("DNC_MY_ADDRESS")
  defp env_value(:phone), do: System.get_env("DNC_MY_PHONE")
  defp env_value(:email), do: System.get_env("DNC_MY_EMAIL")
  defp env_value(:small_claims_county), do: System.get_env("DNC_MY_COUNTY")
  defp env_value(_), do: nil

  defp default_placeholder(:name), do: "[Your Name]"
  defp default_placeholder(:address), do: "[Your Address]"
  defp default_placeholder(:phone), do: "[Your Phone Number]"
  defp default_placeholder(:email), do: "[Your Email Address]"
  defp default_placeholder(:small_claims_county), do: "[Your County]"
  defp default_placeholder(:dnc_registration_date), do: "[Date your number was registered]"
  defp default_placeholder(_), do: nil

  defp present(value) when value in [nil, ""], do: nil
  defp present(%Date{} = value), do: value
  defp present(value), do: value

  defp empty, do: %__MODULE__{}
end

defmodule DncWatchdog.EnforcementFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `DncWatchdog.Enforcement` context.
  """

  @doc """
  Generate a case.
  """
  def case_fixture(attrs \\ %{}) do
    {:ok, case} =
      attrs
      |> Enum.into(%{
        company_name: "some company_name",
        letter_draft: "some letter_draft",
        notes: "some notes",
        status: "new",
        workflow_step: "intake"
      })
      |> DncWatchdog.Enforcement.create_case()

    case
  end

  @doc """
  Case with a linked legal entity whose `legal_name` differs from `company_name`.
  """
  def case_with_legal_entity_fixture(case_attrs \\ %{}, entity_attrs \\ %{}) do
    case =
      case_fixture(Map.merge(%{company_name: "Caller 9254996086"}, case_attrs))

    {:ok, case} =
      DncWatchdog.Enforcement.upsert_case_legal_entity(
        case,
        Map.merge(
          %{
            legal_name: "Equinox Roofing LLC",
            street: "123 Main St",
            city: "San Francisco",
            state: "CA",
            zip: "94105"
          },
          entity_attrs
        )
      )

    case
  end

  def communication_attrs(overrides \\ %{}) do
    {:ok, case} =
      DncWatchdog.Enforcement.create_case(%{
        company_name: "Fixture Company",
        status: "new",
        workflow_step: "intake",
        notes: "",
        letter_draft: ""
      })

    Map.merge(
      %{
        timestamp: ~N[2026-05-20 09:14:00],
        channel: "sms",
        direction: "incoming",
        from_number: "8001234567",
        to_number: "5550001234",
        duration_seconds: 0,
        body: "Limited time offer",
        company: "Fixture Company",
        reasons: "incoming contact from unapproved number",
        case_id: case.id
      },
      overrides
    )
  end

  def communication_fixture(overrides \\ %{}) do
    attrs = communication_attrs(overrides)
    {:ok, communication} = DncWatchdog.Enforcement.create_communication(attrs)
    communication
  end

  def import_row_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        timestamp: ~N[2026-05-20 09:14:00],
        channel: "sms",
        direction: "incoming",
        from_number: "8001234567",
        to_number: "5550001234",
        duration_seconds: 0,
        body: "Limited time offer",
        company: "Acme Imports"
      },
      overrides
    )
  end
end

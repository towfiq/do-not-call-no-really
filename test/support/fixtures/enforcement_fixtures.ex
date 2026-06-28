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

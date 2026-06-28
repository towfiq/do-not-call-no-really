defmodule DncWatchdog.Enforcement.Workflow do
  @moduledoc """
  Validates case workflow transitions and maps steps to statuses.
  """

  alias DncWatchdog.Enforcement.Case
  alias DncWatchdog.Enforcement.LegalEntity

  @steps ~w(intake triage evidence_review draft_review ready_to_send sent archived)

  def steps, do: @steps

  def next_step("intake"), do: "triage"
  def next_step("triage"), do: "evidence_review"
  def next_step("evidence_review"), do: "draft_review"
  def next_step("draft_review"), do: "ready_to_send"
  def next_step("ready_to_send"), do: "sent"
  def next_step("sent"), do: "archived"
  def next_step(step), do: step

  def next_status("sent"), do: "sent"
  def next_status("archived"), do: "closed"
  def next_status("draft_review"), do: "drafting_letter"
  def next_status(_), do: "investigating"

  @doc """
  Returns `:ok` or `{:error, messages}` when the case cannot advance.
  """
  def validate_advance(%Case{} = case, violations, attachments) do
    case next_step(case.workflow_step) do
      "draft_review" ->
        validate_evidence_review(case, violations, attachments)

      "ready_to_send" ->
        validate_draft_review(case)

      _ ->
        :ok
    end
  end

  defp validate_evidence_review(case, violations, attachments) do
    errors = []

    errors =
      if violations == [] do
        ["Mark at least one communication as a violation before drafting a letter." | errors]
      else
        errors
      end

    errors =
      case case.legal_entity do
        %LegalEntity{} = entity ->
          if LegalEntity.mailable?(entity), do: errors, else: [address_message() | errors]

        _ ->
          [address_message() | errors]
      end

    errors =
      if attachments == [] do
        ["Upload at least one screenshot or evidence attachment (recommended before sending)." | errors]
      else
        errors
      end

    if errors == [], do: :ok, else: {:error, Enum.reverse(errors)}
  end

  defp validate_draft_review(case) do
    if blank?(case.letter_draft) do
      {:error, ["Generate or write a letter draft before marking ready to send."]}
    else
      :ok
    end
  end

  defp address_message do
    "Add a legal entity with a complete mailing address (street, city, state, zip)."
  end

  defp blank?(value) when value in [nil, ""], do: true
  defp blank?(_), do: false
end

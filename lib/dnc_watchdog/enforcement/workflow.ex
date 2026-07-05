defmodule DncWatchdog.Enforcement.Workflow do
  @moduledoc """
  Validates case workflow transitions and maps steps to statuses.
  """

  alias DncWatchdog.Enforcement.Case
  alias DncWatchdog.Enforcement.FilingLimits
  alias DncWatchdog.Enforcement.LegalEntity

  @steps ~w(intake triage evidence_review draft_review ready_to_send sent delivered litigation_draft ready_to_file filed archived)

  @phases %{
    "all" => [],
    "triage" => ~w(intake triage evidence_review),
    "letter" => ~w(draft_review ready_to_send),
    "sent" => ~w(sent),
    "delivered" => ~w(delivered),
    "litigation" => ~w(litigation_draft ready_to_file filed),
    "archived" => ~w(archived)
  }

  def steps, do: @steps

  def workflow_phases do
    [
      {"all", "All"},
      {"triage", "Triage"},
      {"letter", "Letter draft"},
      {"sent", "Sent"},
      {"delivered", "Delivered"},
      {"litigation", "In court"},
      {"archived", "Archived"}
    ]
  end

  def steps_for_phase("all"), do: []
  def steps_for_phase(phase), do: Map.get(@phases, phase, [])

  def valid_phase?(phase), do: Map.has_key?(@phases, phase)

  def next_step("intake"), do: "triage"
  def next_step("triage"), do: "evidence_review"
  def next_step("evidence_review"), do: "draft_review"
  def next_step("draft_review"), do: "ready_to_send"
  def next_step("ready_to_send"), do: "sent"
  def next_step("sent"), do: "delivered"
  def next_step("delivered"), do: "litigation_draft"
  def next_step("litigation_draft"), do: "ready_to_file"
  def next_step("ready_to_file"), do: "filed"
  def next_step("filed"), do: "archived"
  def next_step(step), do: step

  def next_status("sent"), do: "sent"
  def next_status("delivered"), do: "delivered"
  def next_status("litigation_draft"), do: "litigating"
  def next_status("ready_to_file"), do: "litigating"
  def next_status("filed"), do: "filed"
  def next_status("archived"), do: "closed"
  def next_status("draft_review"), do: "drafting_letter"
  def next_status(_), do: "investigating"

  @doc """
  Returns `:ok` or `{:error, messages}` when the case cannot advance.
  """
  def validate_advance(%Case{} = case, violations, attachments, opts \\ []) do
    filing_limits = Keyword.get(opts, :filing_limits)

    case next_step(case.workflow_step) do
      "draft_review" ->
        validate_evidence_review(case, violations, attachments)

      "ready_to_send" ->
        validate_draft_review(case)

      "ready_to_file" ->
        validate_litigation_draft(case, violations, filing_limits)

      "filed" ->
        validate_ready_to_file(case)

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
        [
          "Upload at least one screenshot or evidence attachment (recommended before sending)."
          | errors
        ]
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

  defp validate_litigation_draft(case, violations, filing_limits) do
    limits = filing_limits || FilingLimits.assess(length(violations))

    draft_ok? =
      case limits.recommended_venue do
        "small_claims" ->
          case.court_filing_draft not in [nil, ""]

        venue when venue in ["limited_civil", "unlimited_civil"] ->
          case.civil_complaint_draft not in [nil, ""]

        _ ->
          false
      end

    if draft_ok? do
      :ok
    else
      venue_label = FilingLimits.venue_label(limits.recommended_venue)

      {:error,
       [
         "Generate a #{venue_label} draft before marking ready to file (recommended venue based on damages and annual limits)."
       ]}
    end
  end

  defp validate_ready_to_file(case) do
    cond do
      blank_date?(case.court_filed_at) ->
        {:error, ["Record the court filing date before advancing to filed."]}

      blank?(case.court_filed_venue) ->
        {:error, ["Record the court filing venue before advancing to filed."]}

      is_nil(case.court_filed_amount) ->
        {:error, ["Record the amount claimed when filed before advancing to filed."]}

      true ->
        :ok
    end
  end

  defp address_message do
    "Add a legal entity with a complete mailing address (street, city, state, zip)."
  end

  defp blank?(value) when value in [nil, ""], do: true
  defp blank?(_), do: false

  defp blank_date?(nil), do: true
  defp blank_date?(_), do: false
end

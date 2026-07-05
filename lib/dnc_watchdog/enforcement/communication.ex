defmodule DncWatchdog.Enforcement.Communication do
  use Ecto.Schema
  import Ecto.Changeset

  alias DncWatchdog.Enforcement.Phone

  schema "communications" do
    field :timestamp, :naive_datetime
    field :channel, :string
    field :direction, :string
    field :from_number, :string
    field :to_number, :string
    field :duration_seconds, :integer
    field :body, :string
    field :company, :string
    field :reasons, :string
    field :source_fingerprint, :string
    field :violation_status, :string, default: "pending"
    field :spam, DncWatchdog.Ecto.SqliteBoolean, default: false
    belongs_to :case, DncWatchdog.Enforcement.Case
    has_many :evidence_attachments, DncWatchdog.Enforcement.EvidenceAttachment

    timestamps(type: :utc_datetime)
  end

  @doc """
  Stable hash for a communication row so repeat imports do not create duplicates.

  Uses the other party (caller/callee) rather than both endpoints so imports
  still match when `to_number` is `"local"` vs a resolved `DNC_MY_PHONE` value.
  """
  def fingerprint(attrs) when is_map(attrs) do
    parts = [
      timestamp_key(attrs[:timestamp] || attrs["timestamp"]),
      attrs[:channel] || attrs["channel"] || "",
      attrs[:direction] || attrs["direction"] || "",
      peer_key(attrs),
      Integer.to_string(attrs[:duration_seconds] || attrs["duration_seconds"] || 0),
      normalize_body(attrs[:body] || attrs["body"])
    ]

    :crypto.hash(:sha256, Enum.join(parts, "\x1e"))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Computes the import fingerprint for an existing communication record.
  """
  def computed_fingerprint(%__MODULE__{} = communication) do
    fingerprint(%{
      timestamp: communication.timestamp,
      channel: communication.channel,
      direction: communication.direction,
      from_number: communication.from_number,
      to_number: communication.to_number,
      duration_seconds: communication.duration_seconds,
      body: communication.body
    })
  end

  defp normalize_body(nil), do: ""

  defp normalize_body(body) when is_binary(body) do
    body |> String.replace("\r\n", "\n") |> String.trim()
  end

  defp peer_key(attrs) do
    direction = attrs[:direction] || attrs["direction"]

    peer =
      case direction do
        "incoming" -> attrs[:from_number] || attrs["from_number"]
        "outgoing" -> attrs[:to_number] || attrs["to_number"]
        _ -> ""
      end

    Phone.normalize(peer)
  end

  defp timestamp_key(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)

  defp timestamp_key(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(String.replace(value, " ", "T")) do
      {:ok, dt} -> NaiveDateTime.to_iso8601(dt)
      _ -> value
    end
  end

  defp timestamp_key(_), do: ""

  @violation_statuses ~w(pending violation excluded)

  @doc false
  def changeset(communication, attrs) do
    communication
    |> cast(attrs, [
      :timestamp,
      :channel,
      :direction,
      :from_number,
      :to_number,
      :duration_seconds,
      :body,
      :company,
      :reasons,
      :case_id,
      :source_fingerprint,
      :violation_status,
      :spam
    ])
    |> validate_required([:timestamp, :channel, :direction, :from_number, :to_number])
    |> validate_inclusion(:channel, ["call", "sms"])
    |> validate_inclusion(:direction, ["incoming", "outgoing"])
    |> validate_inclusion(:violation_status, @violation_statuses)
  end

  def violation_statuses, do: @violation_statuses
end


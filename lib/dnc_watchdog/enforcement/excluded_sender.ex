defmodule DncWatchdog.Enforcement.ExcludedSender do
  use Ecto.Schema
  import Ecto.Changeset

  alias DncWatchdog.Enforcement.ContactFilter
  alias DncWatchdog.Enforcement.Phone

  schema "excluded_senders" do
    field :peer_key, :string
    field :peer_type, :string
    field :display_peer, :string
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @peer_types ~w(phone email)

  @doc false
  def changeset(excluded_sender, attrs) do
    excluded_sender
    |> cast(attrs, [:peer_key, :peer_type, :display_peer, :notes])
    |> validate_required([:peer_key, :peer_type, :display_peer])
    |> validate_inclusion(:peer_type, @peer_types)
    |> unique_constraint(:peer_key)
  end

  @doc """
  Normalizes a phone number or email into a stable lookup key.
  """
  def peer_key(raw_peer) when is_binary(raw_peer) do
    raw_peer = String.trim(raw_peer)

    cond do
      raw_peer == "" ->
        ""

      ContactFilter.email_peer?(raw_peer) ->
        String.downcase(raw_peer)

      true ->
        Phone.normalize(raw_peer)
    end
  end

  def peer_key(_), do: ""

  @doc """
  Returns `{peer_type, peer_key, display_peer}` or `:invalid`.
  """
  def classify_peer(raw_peer) when is_binary(raw_peer) do
    raw_peer = String.trim(raw_peer)

    cond do
      raw_peer == "" ->
        :invalid

      ContactFilter.email_peer?(raw_peer) ->
        {:email, String.downcase(raw_peer), raw_peer}

      true ->
        key = Phone.normalize(raw_peer)
        if key == "", do: :invalid, else: {:phone, key, raw_peer}
    end
  end

  def classify_peer(_), do: :invalid

  @doc """
  Lookup key for an import row or communication struct.
  """
  def peer_key_for(row) do
    row |> ContactFilter.peer_for() |> peer_key()
  end
end

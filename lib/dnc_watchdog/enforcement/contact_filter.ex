defmodule DncWatchdog.Enforcement.ContactFilter do
  @moduledoc """
  Filters communication rows whose peer appears in macOS Contacts.
  """

  alias DncWatchdog.Enforcement.Phone

  @type contact_set :: %{
          phones: MapSet.t(String.t()),
          emails: MapSet.t(String.t()),
          names: %{optional(String.t()) => String.t()}
        }

  def empty_set do
    %{phones: MapSet.new(), emails: MapSet.new(), names: %{}}
  end

  @doc """
  Copies an Address Book display name onto each row whose peer matches `names`.

  Call History caller-ID (`company`) is left unchanged. `contact_name` is how
  import distinguishes a saved contact from that caller-ID string.
  """
  def apply_names(rows, contact_set) when is_list(rows) do
    names = Map.get(contact_set, :names) || %{}

    if map_size(names) == 0 do
      rows
    else
      Enum.map(rows, &put_contact_name(&1, names))
    end
  end

  defp put_contact_name(row, names) do
    case name_for_peer(peer_for(row), names) do
      name when is_binary(name) and name != "" -> Map.put(row, :contact_name, name)
      _ -> row
    end
  end

  defp name_for_peer(peer, names) do
    cond do
      peer in [nil, ""] ->
        nil

      email_peer?(peer) ->
        Map.get(names, String.downcase(peer))

      true ->
        peer |> Phone.lookup_keys() |> Enum.find_value(&Map.get(names, &1))
    end
  end

  @doc """
  Returns true when the row's peer (other party) is in the contact set.
  """
  def contact_row?(row, %{phones: phones, emails: emails}) do
    peer = peer_for(row)

    cond do
      peer in [nil, ""] ->
        false

      email_peer?(peer) ->
        MapSet.member?(emails, String.downcase(peer))

      true ->
        Phone.contact_member?(peer, phones)
    end
  end

  def reject_contacts(rows, contact_set) do
    {kept, skipped} =
      Enum.split_with(rows, fn row -> not contact_row?(row, contact_set) end)

    {kept, length(skipped)}
  end

  @doc """
  Rejects persisted communications whose peer is in `contact_set`.
  """
  def reject_contact_communications(communications, contact_set) when is_list(communications) do
    Enum.reject(communications, &contact_communication?(&1, contact_set))
  end

  def contact_communication?(communication, contact_set) do
    contact_row?(row_from_communication(communication), contact_set)
  end

  def row_from_communication(%{direction: direction, from_number: from, to_number: to}) do
    %{direction: direction, from_number: from || "", to_number: to || ""}
  end

  @doc """
  The other party on a communication (caller/sender for incoming, callee for outgoing).
  """
  def peer_for(%{direction: "incoming", from_number: from}), do: from
  def peer_for(%{direction: "outgoing", to_number: to}), do: to
  def peer_for(_), do: ""

  def email_peer?(peer) do
    peer = to_string(peer)
    String.contains?(peer, "@")
  end
end

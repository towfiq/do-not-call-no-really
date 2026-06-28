defmodule DncWatchdog.Enforcement.ContactFilter do
  @moduledoc """
  Filters communication rows whose peer appears in macOS Contacts.
  """

  alias DncWatchdog.Enforcement.Phone

  @type contact_set :: %{
          phones: MapSet.t(String.t()),
          emails: MapSet.t(String.t())
        }

  def empty_set do
    %{phones: MapSet.new(), emails: MapSet.new()}
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

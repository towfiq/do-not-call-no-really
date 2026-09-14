defmodule DncWatchdog.Enforcement.CommunicationGroups do
  @moduledoc """
  Groups communications by the other party (caller for incoming, callee for outgoing).
  """

  alias DncWatchdog.Enforcement.ContactFilter
  alias DncWatchdog.Enforcement.Phone

  @type group :: %{
          peer: String.t(),
          label: String.t(),
          communications: [map()],
          latest: map()
        }

  @doc """
  Groups rows by normalized peer phone/email, newest group first.
  """
  @spec group_by_peer([map()]) :: [group()]
  def group_by_peer(communications) when is_list(communications) do
    communications
    |> Enum.group_by(&peer_key/1)
    |> Enum.map(&build_group/1)
    |> Enum.sort_by(& &1.latest.timestamp, {:desc, NaiveDateTime})
  end

  defp build_group({peer, communications}) do
    sorted = Enum.sort_by(communications, & &1.timestamp, {:desc, NaiveDateTime})

    %{
      peer: peer,
      label: peer_label(peer),
      communications: sorted,
      latest: hd(sorted)
    }
  end

  def peer_key(communication) do
    communication
    |> ContactFilter.peer_for()
    |> Phone.normalize()
    |> case do
      "" -> "unknown"
      peer -> peer
    end
  end

  defp peer_label("unknown"), do: "Unknown sender"
  defp peer_label(peer), do: peer
end

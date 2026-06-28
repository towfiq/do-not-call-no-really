defmodule DncWatchdog.Enforcement.Local.Paths do
  @moduledoc """
  Default macOS paths for Messages and Call History SQLite databases.
  """

  def messages_db(override \\ nil) do
    override ||
      Path.expand("~/Library/Messages/chat.db")
  end

  def call_history_db(override \\ nil) do
    override ||
      Enum.find_value(default_call_history_paths(), fn path ->
        if File.exists?(path), do: path
      end)
  end

  def contacts_dbs(override \\ nil) do
    case override do
      nil -> discover_contacts_dbs()
      path when is_binary(path) -> [path]
      paths when is_list(paths) -> paths
    end
  end

  def discover_contacts_dbs do
    discover_contacts_dbs_under(Path.expand("~/Library/Application Support/AddressBook"))
  end

  @doc false
  def discover_contacts_dbs_under(base) do
    if File.exists?(base) do
      legacy =
        base
        |> Path.join("**/AddressBook.sqlitedb")
        |> Path.wildcard()

      modern =
        base
        |> Path.join("**/AddressBook*.abcddb")
        |> Path.wildcard()

      (legacy ++ modern)
      |> Enum.filter(&File.regular?/1)
      |> Enum.uniq()
      |> Enum.sort()
    else
      []
    end
  end

  def default_call_history_paths do
    [
      Path.expand("~/Library/Application Support/CallHistoryDB/CallHistory.storedata"),
      Path.expand(
        "~/Library/Application Support/com.apple.TelephonyUtilities/CallHistoryDB/CallHistory.storedata"
      )
    ]
  end
end

defmodule Mix.Tasks.Dnc.CheckContact do
  use Mix.Task

  @shortdoc "Check whether phone numbers appear in macOS Contacts databases"

  @impl Mix.Task
  def run(args) do
    phones = Enum.reject(args, &(&1 == ""))

    if phones == [] do
      Mix.shell().error("Usage: mix dnc.check_contact 6504653718 8476688844")
      exit({:shutdown, 1})
    end

    Mix.Task.run("app.start")

    alias DncWatchdog.Enforcement.ContactFilter
    alias DncWatchdog.Enforcement.Local.Contacts
    alias DncWatchdog.Enforcement.Local.Paths
    alias DncWatchdog.Enforcement.Phone

    discovered = Paths.discover_contacts_dbs()

    Mix.shell().info("Discovered #{length(discovered)} Contacts database(s):")
    Enum.each(discovered, &Mix.shell().info("  #{&1}"))

    if discovered == [] do
      Mix.shell().error("")

      Mix.shell().error(
        "No Contacts databases found under ~/Library/Application Support/AddressBook."
      )

      Mix.shell().error("Expected AddressBook-v22.abcddb (root or Sources/*/).")

      Mix.shell().error(
        "Grant Full Disk Access to Terminal/Cursor, or pass --contacts-db explicitly."
      )

      exit({:shutdown, 1})
    end

    case Contacts.load() do
      {:ok, set, loaded} ->
        Mix.shell().info("")

        Mix.shell().info(
          "Loaded #{MapSet.size(set.phones)} phone key(s) and #{MapSet.size(set.emails)} email(s) from #{length(loaded)} readable database(s)"
        )

        Mix.shell().info("")

        Enum.each(phones, fn phone ->
          keys = Phone.lookup_keys(phone)
          normalized = Phone.normalize(phone)

          in_set? = Enum.any?(keys, &MapSet.member?(set.phones, &1))

          row = %{direction: "incoming", from_number: phone, to_number: ""}
          would_skip? = ContactFilter.contact_row?(row, set)

          Mix.shell().info("#{phone} -> #{normalized}")
          Mix.shell().info("  lookup keys: #{inspect(keys)}")
          Mix.shell().info("  in contact set: #{in_set?}")
          Mix.shell().info("  would skip on import: #{would_skip?}")
        end)

      {:error, {:contacts_unreadable, errors}} ->
        Mix.shell().error("Could not read Contacts databases:")

        Enum.each(errors, fn {path, reason} ->
          Mix.shell().error("  #{path}: #{inspect(reason)}")
        end)

        exit({:shutdown, 1})
    end
  end
end

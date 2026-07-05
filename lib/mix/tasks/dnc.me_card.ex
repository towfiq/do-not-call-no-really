defmodule Mix.Tasks.Dnc.MeCard do
  use Mix.Task

  @shortdoc "Print your macOS Contacts Me card details"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    alias DncWatchdog.Enforcement.Local.MeCard

    case MeCard.read() do
      {:ok, card} ->
        Mix.shell().info("Me card found:")

        Enum.each([:name, :address, :phone, :email], fn key ->
          value = Map.get(card, key)

          Mix.shell().info(
            "  #{key}: #{if value, do: String.replace(value, "\n", " / "), else: "(not set)"}"
          )
        end)

        Mix.shell().info("")
        Mix.shell().info("Import into the app with the Import from Contacts button on /settings")

      {:error, :not_found} ->
        Mix.shell().error("No Me card found. Add your card in Contacts with a mailing address.")

      {:error, {:contacts_unreadable, errors}} ->
        Mix.shell().error("Could not read Contacts databases:")

        Enum.each(errors, fn {path, reason} ->
          Mix.shell().error("  #{path}: #{inspect(reason)}")
        end)

        Mix.shell().error("Grant Full Disk Access to Terminal or Cursor and try again.")
    end
  end
end

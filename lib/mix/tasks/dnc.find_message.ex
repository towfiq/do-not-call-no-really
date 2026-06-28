defmodule Mix.Tasks.Dnc.FindMessage do
  use Mix.Task

  @shortdoc "Search macOS Messages chat.db for a phone number and show decode details"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    phone = List.first(args)

    if is_nil(phone) or phone == "" do
      Mix.shell().error("Usage: mix dnc.find_message 8187432556")
      exit({:shutdown, 1})
    end

    path = DncWatchdog.Enforcement.Local.Paths.messages_db(nil)

    Mix.shell().info("Searching #{path} for #{phone} ...")
    Mix.shell().info("")

    case DncWatchdog.Enforcement.Local.Messages.search(path, phone) do
      {:ok, []} ->
        Mix.shell().info("No rows found in chat.db for that number.")
        Mix.shell().info("")
        Mix.shell().info("If the text appears in Messages.app, check Junk/Filtered and quit Messages before re-running.")

      {:ok, hits} ->
        Mix.shell().info("Found #{length(hits)} row(s):")
        Mix.shell().info("")

        Enum.each(hits, fn hit ->
          Mix.shell().info(
            "ROWID #{hit.rowid} @ #{hit.timestamp} from_me=#{hit.is_from_me} handle=#{hit.handle_id || "—"} chat=#{hit.chat_identifier || "—"}"
          )

          Mix.shell().info(
            "  text=#{hit.text_length} chars, attributedBody=#{hit.attributed_body_length} bytes"
          )

          preview =
            hit.decoded_body
            |> String.replace("\n", " ")
            |> String.slice(0, 120)

          Mix.shell().info("  decoded: #{if preview == "", do: "(empty — decode failed)", else: preview}")
          Mix.shell().info("")
        end)

      {:error, reason} ->
        Mix.shell().error(reason)
        exit({:shutdown, 1})
    end
  end
end

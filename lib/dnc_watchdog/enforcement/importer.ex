defmodule DncWatchdog.Enforcement.Importer do
  @moduledoc """
  Imports normalized communication CSV rows and upserts case records.
  """

  alias DncWatchdog.Enforcement.Phone
  alias DncWatchdog.Enforcement.RowImporter

  def import_csv(path) do
    path
    |> File.stream!()
    |> Stream.drop(1)
    |> Stream.reject(&(String.trim(&1) == ""))
    |> Stream.map(&parse_line/1)
    |> RowImporter.import_rows()
  end

  defp parse_line(line) do
    fields =
      line
      |> String.trim_trailing("\n")
      |> String.split(",", parts: 8)
      |> pad_fields(8)

    [timestamp, channel, direction, from_number, to_number, duration_seconds, body, company] =
      fields

    %{
      timestamp: timestamp,
      channel: String.downcase(channel),
      direction: String.downcase(direction),
      from_number: Phone.normalize(from_number),
      to_number: Phone.normalize(to_number),
      duration_seconds: parse_int(duration_seconds),
      body: body,
      company: company
    }
  end

  defp parse_int(value) do
    case Integer.parse(to_string(value)) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp pad_fields(fields, size) when length(fields) < size do
    pad_fields(fields ++ [""], size)
  end

  defp pad_fields(fields, _size), do: fields
end

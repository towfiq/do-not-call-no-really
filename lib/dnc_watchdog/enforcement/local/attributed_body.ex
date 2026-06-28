defmodule DncWatchdog.Enforcement.Local.AttributedBody do
  @moduledoc """
  Extracts plain text from macOS Messages `attributedBody` typedstream blobs.

  On Ventura and later, many rows store message text only in `attributedBody`
  (NSAttributedString archived as typedstream), not in the `text` column.
  """

  @marker <<0x01, 0x2B>>

  @doc """
  Returns decoded UTF-8 text, or `nil` when the blob cannot be parsed.
  """
  def extract_text(blob) when is_binary(blob) and blob != "" do
    blob
    |> marker_positions()
    |> Enum.map(fn pos -> extract_at(blob, pos) end)
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 == ""))
    |> longest()
  end

  def extract_text(_), do: nil

  defp marker_positions(blob) do
    marker_positions(blob, 0, [])
  end

  defp marker_positions(blob, offset, acc) when offset < byte_size(blob) do
    case :binary.match(blob, @marker, scope: {offset, byte_size(blob) - offset}) do
      {pos, _} -> marker_positions(blob, pos + 1, [pos | acc])
      :nomatch -> Enum.reverse(acc)
    end
  end

  defp marker_positions(_blob, _offset, acc), do: Enum.reverse(acc)

  defp extract_at(blob, pos) do
    blob
    |> binary_part(pos + 2, byte_size(blob) - pos - 2)
    |> read_length_prefixed_text()
  end

  defp longest([]), do: nil
  defp longest(texts), do: Enum.max_by(texts, &String.length/1)

  defp read_length_prefixed_text(<<>>), do: nil

  defp read_length_prefixed_text(<<tag, rest::binary>>) when tag <= 0x7F do
    take_text(rest, tag)
  end

  defp read_length_prefixed_text(<<0x81, len::little-unsigned-size(16), rest::binary>>) do
    take_text(rest, len)
  end

  defp read_length_prefixed_text(<<0x82, len::little-unsigned-size(32), rest::binary>>) do
    take_text(rest, len)
  end

  defp read_length_prefixed_text(_), do: nil

  defp take_text(rest, len) when byte_size(rest) >= len do
    <<text::binary-size(len), _::binary>> = rest

    case String.valid?(text) do
      true -> text
      false -> nil
    end
  end

  defp take_text(_rest, _len), do: nil
end

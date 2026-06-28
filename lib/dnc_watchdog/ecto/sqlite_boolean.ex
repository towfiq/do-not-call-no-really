defmodule DncWatchdog.Ecto.SqliteBoolean do
  @moduledoc false

  use Ecto.Type

  @true_values ~w(1 true TRUE)
  @false_values ~w(0 false FALSE)

  def type, do: :boolean

  def cast(value), do: Ecto.Type.cast(:boolean, value)

  def load(value) when is_boolean(value), do: {:ok, value}
  def load(value) when is_integer(value), do: {:ok, value != 0}

  def load(value) when is_binary(value) do
    cond do
      value in @true_values -> {:ok, true}
      value in @false_values -> {:ok, false}
      true -> :error
    end
  end

  def load(_), do: :error

  def dump(nil), do: {:ok, nil}
  def dump(value) when is_boolean(value), do: {:ok, value}
  def dump(_), do: :error
end

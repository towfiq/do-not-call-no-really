defmodule DncWatchdog.Enforcement.PurgeSelfInitiated do
  @moduledoc """
  Deletes stored communications you initiated (outgoing SMS/calls).
  """

  import Ecto.Query, warn: false

  alias DncWatchdog.Enforcement.Communication
  alias DncWatchdog.Enforcement.Phone
  alias DncWatchdog.Enforcement.SelfInitiatedFilter
  alias DncWatchdog.Repo

  @type summary :: %{
          total: non_neg_integer(),
          matched: non_neg_integer(),
          deleted: non_neg_integer(),
          dry_run: boolean()
        }

  @doc """
  Removes communications matching `SelfInitiatedFilter` for `my_phone`.

  `my_phone` may be nil to use `DNC_MY_PHONE`. Returns `{:error, :my_phone_required}`
  when no phone is configured.
  """
  @spec purge(keyword()) :: {:ok, summary()} | {:error, :my_phone_required}
  def purge(opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)

    my_phone =
      opts
      |> Keyword.get(:my_phone)
      |> Phone.normalize_or_env()

    if my_phone == "" do
      {:error, :my_phone_required}
    else
      communications = Repo.all(from c in Communication, order_by: [asc: c.id])

      {to_remove, kept} =
        Enum.split_with(communications, &SelfInitiatedFilter.self_initiated_row?(&1, my_phone))

      deleted =
        if dry_run? do
          length(to_remove)
        else
          Enum.reduce(to_remove, 0, fn comm, count ->
            case Repo.delete(comm) do
              {:ok, _} -> count + 1
              {:error, _} -> count
            end
          end)
        end

      {:ok,
       %{
         total: length(communications),
         matched: length(to_remove),
         deleted: deleted,
         remaining: length(kept),
         dry_run: dry_run?
       }}
    end
  end
end

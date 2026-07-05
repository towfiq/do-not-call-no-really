defmodule DncWatchdog do
  @moduledoc """
  DncWatchdog keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  use Boundary,
    deps: [Ecto, Ecto.Changeset, Ecto.Adapters.SQL, Exqlite, Finch, Jason, ChromicPDF, Swoosh],
    exports: [
      Repo,
      {Enforcement, []}
    ]
end

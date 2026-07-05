defmodule Mix.Tasks.Dnc do
  @moduledoc false

  use Boundary,
    deps: [DncWatchdog, Ecto.Changeset, Mix],
    exports: :all
end

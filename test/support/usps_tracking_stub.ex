defmodule DncWatchdog.Enforcement.UspsTracking.StubPageFetcher do
  @moduledoc false

  def fetch(_url) do
    {:ok,
     Jason.encode!(%{
       "blocked" => false,
       "text" =>
         "Tracking Number: 9400 1118 9922 3197 4284 90 Delivered, In/At Mailbox Your item was delivered at 3:14 pm on June 1, 2026.",
       "summary" => "Your item was delivered at 3:14 pm on June 1, 2026."
     })}
  end
end

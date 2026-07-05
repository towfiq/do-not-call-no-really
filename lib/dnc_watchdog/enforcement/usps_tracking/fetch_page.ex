defmodule DncWatchdog.Enforcement.UspsTracking.FetchPage do
  @moduledoc false

  import ChromicPDF.ProtocolMacros

  steps do
    include_protocol(ChromicPDF.Navigate)

    call(
      :extract,
      "Runtime.evaluate",
      fn _state ->
        %{
          "expression" => DncWatchdog.Enforcement.UspsTracking.extract_page_script(),
          "awaitPromise" => true,
          "returnByValue" => true
        }
      end,
      %{}
    )

    await_response(:extracted, [{["result", "value"], "page_json"}])

    include_protocol(ChromicPDF.ResetTarget)

    output("page_json")
  end
end

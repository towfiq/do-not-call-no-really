defmodule DncWatchdog.Enforcement.UspsTracking.FetchPage do
  @moduledoc false

  import ChromicPDF.ProtocolMacros

  @user_agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " <>
                "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

  steps do
    call(
      :set_ua,
      "Emulation.setUserAgentOverride",
      fn _state ->
        %{"userAgent" => @user_agent}
      end,
      %{}
    )

    await_response(:ua_set, [])

    call(:navigate, "Page.navigate", [:url], %{})

    await_response(:navigated, ["frameId"]) do
      case get_in(msg, ["result", "errorText"]) do
        nil ->
          :ok

        error ->
          {:error, error}
      end
    end

    await_notification(:dom_content, "Page.domContentEventFired", [], [])

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

    await_response(:extracted, [{["result", "value"], "page_json"}]) do
      case get_in(msg, ["result", "exceptionDetails"]) do
        nil ->
          :ok

        error ->
          {:error, {:evaluate, inspect(error)}}
      end
    end

    include_protocol(ChromicPDF.ResetTarget)

    output("page_json")
  end
end

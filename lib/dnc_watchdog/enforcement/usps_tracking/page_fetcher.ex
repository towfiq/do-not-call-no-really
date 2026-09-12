defmodule DncWatchdog.Enforcement.UspsTracking.PageFetcher do
  @moduledoc false

  require Logger

  alias DncWatchdog.Enforcement.LetterPdf
  alias DncWatchdog.Enforcement.UspsTracking.FetchPage

  @online_timeout 45_000

  def fetch(url) when is_binary(url) do
    with :ok <- LetterPdf.ensure_chromic_pdf!() do
      case ChromicPDF.run_protocol(FetchPage, fetch_opts(url)) do
        {:ok, page_json} when is_binary(page_json) ->
          {:ok, page_json}

        {:error, reason} ->
          {:error, {:chromic_pdf, format_reason(reason)}}

        page_json when is_binary(page_json) ->
          {:ok, page_json}

        other ->
          {:error, {:chromic_pdf, "Unexpected Chrome response: #{inspect(other, limit: 50)}"}}
      end
    end
  rescue
    error in ChromicPDF.Browser.ExecutionError ->
      {:error, {:chromic_pdf, Exception.message(error)}}

    error ->
      Logger.warning(
        "[UspsTracking] page fetch failed: #{Exception.format(:error, error, __STACKTRACE__)}"
      )

      {:error, {:chromic_pdf, Exception.message(error)}}
  end

  defp fetch_opts(url) do
    [
      session_pool: :online,
      offline: false,
      source_type: :url,
      url: url,
      timeout: @online_timeout,
      init_timeout: @online_timeout,
      checkout_timeout: @online_timeout
    ]
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end

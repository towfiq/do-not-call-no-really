defmodule DncWatchdog.Enforcement.UspsTracking.PageFetcher do
  @moduledoc false

  alias DncWatchdog.Enforcement.LetterPdf
  alias DncWatchdog.Enforcement.UspsTracking.FetchPage

  @online_timeout 45_000

  def fetch(url) when is_binary(url) do
    with :ok <- LetterPdf.ensure_chromic_pdf!() do
      ChromicPDF.run_protocol(FetchPage, fetch_opts(url))
    end
  rescue
    error in ChromicPDF.Browser.ExecutionError ->
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
end

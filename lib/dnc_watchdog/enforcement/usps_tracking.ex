defmodule DncWatchdog.Enforcement.UspsTracking do
  @moduledoc """
  Looks up USPS tracking status by loading the public tracking page in Chrome
  and parsing the rendered result.

  Requires Google Chrome or Chromium (same dependency as PDF export via ChromicPDF).
  """

  require Logger

  alias DncWatchdog.Enforcement.LetterPdf
  alias DncWatchdog.Enforcement.UspsTracking.PageFetcher

  @delivery_statuses ~w(pending pre_shipment in_transit out_for_delivery delivered returned alert unknown)

  @doc """
  Returns true when Chrome/ChromicPDF is available for page lookups.
  """
  def configured? do
    LetterPdf.ensure_chromic_pdf!() == :ok
  end

  @doc """
  Normalizes a tracking number to digits only.
  """
  def normalize_tracking_number(number) when is_binary(number) do
    number
    |> String.trim()
    |> String.replace(~r/[^0-9A-Za-z]/, "")
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  def normalize_tracking_number(_), do: nil

  @doc """
  Public USPS tracking page URL for a tracking number.
  """
  def tracking_url(number) when is_binary(number) do
    case normalize_tracking_number(number) do
      nil -> nil
      normalized -> "https://tools.usps.com/go/TrackConfirmAction?qtc_tLabels1=#{normalized}"
    end
  end

  @doc """
  Looks up tracking status from the USPS tracking page.

  Returns `{:ok, result}` where result contains:
    * `:delivery_status` — one of #{inspect(@delivery_statuses)}
    * `:summary` — human-readable status text from USPS
    * `:checked_at` — UTC datetime of the lookup

  Or `{:error, reason}` where reason may be `:invalid_tracking_number`,
  `:not_found`, `:blocked`, `:chromic_pdf_unavailable`, `:chromic_pdf_not_started`,
  or `{:http_error, status}`.
  """
  def lookup(tracking_number) do
    case normalize_tracking_number(tracking_number) do
      nil ->
        {:error, :invalid_tracking_number}

      number ->
        with {:ok, url} <- tracking_page_url(number),
             {:ok, page_json} <- page_fetcher().fetch(url),
             {:ok, parsed} <- parse_page_json(page_json) do
          {:ok,
           Map.merge(parsed, %{
             checked_at: DateTime.utc_now() |> DateTime.truncate(:second)
           })}
        end
    end
  rescue
    error ->
      Logger.warning("[UspsTracking] lookup failed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:error, :lookup_failed}
  end

  @doc """
  Client-side script used by ChromicPDF to wait for the USPS page to render
  and return page text as JSON.
  """
  def extract_page_script do
    """
    (async () => {
      const sleep = ms => new Promise(r => setTimeout(r, ms));
      const normalize = value => (value || "").replace(/\\s+/g, " ").trim();
      const deadline = Date.now() + 15000;

      while (Date.now() < deadline) {
        const text = normalize(document.body?.innerText);
        const html = document.documentElement?.outerHTML || "";

        if (/access denied/i.test(text) || /access denied/i.test(html)) {
          return JSON.stringify({blocked: true, text, summary: "USPS blocked automated access"});
        }

        if (/status not available|not yet available|invalid tracking|no tracking information/i.test(text)) {
          return JSON.stringify({blocked: false, text, summary: text.slice(0, 240), not_found: true});
        }

        if (/tracking number|delivered|in transit|out for delivery|label created|pre-shipment|arriving|accepted|departed|processed through|available for pickup|returned to sender|refused|undeliverable/i.test(text)) {
          return JSON.stringify({blocked: false, text, summary: text.slice(0, 240), url: location.href, title: document.title});
        }

        await sleep(250);
      }

      const text = normalize(document.body?.innerText);
      return JSON.stringify({blocked: false, text, summary: text.slice(0, 240), timeout: true, url: location.href, title: document.title});
    })()
    """
  end

  @doc """
  Parses JSON returned from the browser extraction script.
  """
  def parse_page_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{"blocked" => true} = data} ->
        {:error, {:blocked, Map.get(data, "summary", "USPS blocked automated access")}}

      {:ok, %{"not_found" => true}} ->
        {:error, :not_found}

      {:ok, data} when is_map(data) ->
        text = Map.get(data, "text", "")

        cond do
          blank?(text) ->
            {:error, :not_found}

          not tracking_page?(text) ->
            {:error, :not_found}

          true ->
            {:ok,
             %{
               delivery_status: delivery_status_from_text(text),
               summary: summary_from_page(data, text)
             }}
        end

      {:error, _} ->
        {:error, :parse_failed}
    end
  end

  @doc """
  Parses a USPS Tracking API v3 JSON response into delivery status and summary.

  Kept for backwards compatibility with older tests and fixtures.
  """
  def parse_response(body) when is_map(body) do
    status = Map.get(body, "status", "")
    category = Map.get(body, "statusCategory", "")
    summary = Map.get(body, "statusSummary") || status
    events = Map.get(body, "trackingEvents", [])

    %{
      delivery_status: delivery_status_from_usps(category, status, events),
      summary: summary
    }
  end

  def delivery_statuses, do: @delivery_statuses

  defp tracking_page_url(number) do
    case tracking_url(number) do
      nil -> {:error, :invalid_tracking_number}
      url -> {:ok, url}
    end
  end

  defp page_fetcher do
    config()[:page_fetcher] || PageFetcher
  end

  defp config, do: Application.get_env(:dnc_watchdog, :usps_tracking, [])

  defp summary_from_page(data, text) do
    case data["summary"] do
      summary when is_binary(summary) ->
        case String.trim(summary) do
          "" -> extract_summary(text)
          trimmed -> trimmed
        end

      _ ->
        extract_summary(text)
    end
  end

  defp extract_summary(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.find_value("", fn line ->
      line_lc = String.downcase(line)

      if String.length(line) >= 12 and
           (String.contains?(line_lc, "delivered") or
              String.contains?(line_lc, "out for delivery") or
              String.contains?(line_lc, "in transit") or
              String.contains?(line_lc, "returned") or
              String.contains?(line_lc, "refused") or
              String.contains?(line_lc, "accepted") or
              String.contains?(line_lc, "departed") or
              String.contains?(line_lc, "label created") or
              String.contains?(line_lc, "pre-shipment") or
              String.contains?(line_lc, "available for pickup")) do
        line
      end
    end)
  end

  defp delivery_status_from_text(text) do
    text_lc = String.downcase(text)

    cond do
      returned_status?(text_lc) ->
        "returned"

      String.contains?(text_lc, "delivered") ->
        "delivered"

      String.contains?(text_lc, "out for delivery") ->
        "out_for_delivery"

      String.contains?(text_lc, "pre-shipment") or String.contains?(text_lc, "label created") ->
        "pre_shipment"

      String.contains?(text_lc, "delivery status alert") or
          String.contains?(text_lc, "alert -") ->
        "alert"

      String.contains?(text_lc, "in transit") or
          String.contains?(text_lc, "departed") or
          String.contains?(text_lc, "accepted") or
          String.contains?(text_lc, "processed through") or
          String.contains?(text_lc, "arrived at") or
          String.contains?(text_lc, "in possession") ->
        "in_transit"

      true ->
        "unknown"
    end
  end

  defp delivery_status_from_usps(category, status, events) do
    category_lc = String.downcase(category || "")
    status_lc = String.downcase(status || "")

    latest_event_type =
      events
      |> List.first(%{})
      |> Map.get("eventType", "")
      |> String.downcase()

    combined = "#{category_lc} #{status_lc} #{latest_event_type}"

    cond do
      returned_status?(combined) ->
        "returned"

      category_lc == "delivered" or String.contains?(status_lc, "delivered") ->
        "delivered"

      String.contains?(status_lc, "out for delivery") or
          String.contains?(latest_event_type, "out for delivery") ->
        "out_for_delivery"

      category_lc in ["pre-shipment", "pre_shipment"] or
          String.contains?(status_lc, "pre-shipment") ->
        "pre_shipment"

      category_lc == "alert" ->
        "alert"

      category_lc in ["accepted", "in transit", "in_transit"] or
          String.contains?(status_lc, "in transit") or
          String.contains?(status_lc, "in possession") ->
        "in_transit"

      true ->
        "unknown"
    end
  end

  defp returned_status?(text) do
    Enum.any?(
      [
        "return to sender",
        "returned to sender",
        "returned to",
        "refused",
        "undeliverable",
        "unclaimed",
        "addressee unknown",
        "no such number",
        "insufficient address"
      ],
      &String.contains?(text, &1)
    )
  end

  defp tracking_page?(text) do
    text_lc = String.downcase(text)

    status_markers = [
      "tracking history",
      "status not available",
      "label created",
      "delivered",
      "in transit",
      "out for delivery",
      "returned to sender",
      "accepted",
      "departed",
      "processed through"
    ]

    cond do
      String.contains?(text_lc, "tracking number") ->
        true

      String.contains?(text_lc, "skip all category navigation") ->
        false

      true ->
        Enum.any?(status_markers, &String.contains?(text_lc, &1))
    end
  end

  defp blank?(value) when value in [nil, ""], do: true
  defp blank?(_), do: false
end

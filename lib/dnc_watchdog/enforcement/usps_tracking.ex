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

  @progress_steps [
    %{id: :validate, label: "Validate tracking number"},
    %{id: :chrome, label: "Check Chrome"},
    %{id: :fetch, label: "Load USPS tracking page"},
    %{id: :parse, label: "Read tracking status"},
    %{id: :save, label: "Save status to this case"}
  ]

  @browser_helper_steps [
    %{id: :validate, label: "Validate tracking number"},
    %{id: :open_browser, label: "Open USPS tracking in your browser"},
    %{id: :wait_helper, label: "Wait for the browser helper"},
    %{id: :parse, label: "Read tracking status"},
    %{id: :save, label: "Save status to this case"}
  ]

  @doc """
  Returns true when Chrome/ChromicPDF is available for page lookups.
  """
  def configured? do
    LetterPdf.ensure_chromic_pdf!() == :ok
  end

  @doc """
  Ordered steps for a tracking refresh, used by the progress dialog.

  Pass `:browser_helper` for interactive Refresh, or `:chromic` for headless Chrome.
  """
  def progress_steps(mode \\ :chromic)

  def progress_steps(:browser_helper) do
    pending_steps(@browser_helper_steps)
  end

  def progress_steps(_mode) do
    pending_steps(@progress_steps)
  end

  defp pending_steps(steps) do
    Enum.map(steps, fn step ->
      Map.merge(step, %{status: :pending, detail: nil})
    end)
  end

  @doc """
  Sends a progress update to an optional `on_step` callback.
  """
  def emit_progress(on_step, id, status, detail \\ nil)

  def emit_progress(on_step, id, status, detail) when is_function(on_step, 1) do
    message = "[UspsTracking] #{id} #{status}" <> if(detail, do: " — #{detail}", else: "")

    if status == :error do
      Logger.warning(message)
    else
      Logger.info(message)
    end

    on_step.(%{id: id, status: status, detail: detail})
    :ok
  rescue
    error ->
      Logger.warning("[UspsTracking] progress callback failed: #{Exception.message(error)}")

      :ok
  end

  def emit_progress(_on_step, _id, _status, _detail), do: :ok

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

  Options:

    * `:on_step` — `fn %{id: atom, status: atom, detail: String.t() | nil} -> any`

  Returns `{:ok, result}` where result contains:
    * `:delivery_status` — one of #{inspect(@delivery_statuses)}
    * `:summary` — human-readable status text from USPS
    * `:checked_at` — UTC datetime of the lookup

  Or `{:error, reason}` where reason may be `:invalid_tracking_number`,
  `:not_found`, `:blocked`, `:chromic_pdf_unavailable`, `:chromic_pdf_not_started`,
  `:page_timeout`, `:parse_failed`, `{:http_error, status}`, or a tagged tuple
  with extra detail.
  """
  def lookup(tracking_number, opts \\ []) do
    on_step = Keyword.get(opts, :on_step, fn _ -> :ok end)

    emit_progress(on_step, :validate, :running)

    case normalize_tracking_number(tracking_number) do
      nil ->
        emit_progress(on_step, :validate, :error, error_message(:invalid_tracking_number))
        {:error, :invalid_tracking_number}

      number ->
        emit_progress(on_step, :validate, :ok, number)
        lookup_number(number, on_step)
    end
  rescue
    error ->
      Logger.warning(
        "[UspsTracking] lookup failed: #{Exception.format(:error, error, __STACKTRACE__)}"
      )

      {:error, {:lookup_failed, Exception.message(error)}}
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
      const collectText = () => {
        const parts = [];
        const visit = (node) => {
          if (!node) return;
          if (node.innerText) parts.push(node.innerText);
          const elements = node.querySelectorAll ? node.querySelectorAll("*") : [];
          for (const el of elements) {
            if (el.shadowRoot) visit(el.shadowRoot);
          }
        };
        visit(document.body);
        for (const frame of Array.from(document.querySelectorAll("iframe"))) {
          try {
            visit(frame.contentDocument?.body);
          } catch (_err) {}
        }
        return normalize(parts.join(" "));
      };
      const snapshot = (extra) => {
        const text = collectText();
        const html = document.documentElement?.outerHTML || "";
        return Object.assign({
          blocked: false,
          text,
          summary: text.slice(0, 240),
          url: location.href,
          title: document.title,
          readyState: document.readyState,
          htmlLength: html.length,
          iframeCount: document.querySelectorAll("iframe").length,
          html: html.replace(/\\s+/g, " ").trim().slice(0, 240)
        }, extra);
      };
      const deadline = Date.now() + 20000;

      while (Date.now() < deadline) {
        const text = collectText();
        const html = document.documentElement?.outerHTML || "";

        if (/access denied/i.test(text) || /access denied/i.test(html)) {
          return JSON.stringify({blocked: true, text, summary: "USPS blocked automated access", url: location.href, title: document.title});
        }

        if (/status not available|not yet available|invalid tracking|no tracking information/i.test(text)) {
          return JSON.stringify({blocked: false, text, summary: text.slice(0, 240), not_found: true, url: location.href, title: document.title});
        }

        const hasStatus = /tracking history|your item was delivered|delivered,|out for delivery|label created|pre-shipment|in transit|returned to sender|available for pickup|moving through the network/i.test(text);

        if (hasStatus) {
          const summaryMatch = text.match(/your item was delivered[^.]{0,120}|delivered,[^.]{0,80}|out for delivery[^.]{0,80}|in transit[^.]{0,100}|moving through the network[^.]{0,80}|label created[^.]{0,80}|pre-shipment[^.]{0,80}|returned to sender[^.]{0,80}/i);
          const summary = (summaryMatch && summaryMatch[0] || text).replace(/\\s+/g, " ").trim().slice(0, 240);
          return JSON.stringify({blocked: false, text, summary, url: location.href, title: document.title});
        }

        await sleep(250);
      }

      return JSON.stringify(snapshot({timeout: true}));
    })()
    """
  end

  @doc """
  Parses a map posted by the Chrome or Safari helper (or equivalent JSON).
  """
  def parse_helper_payload(params) when is_map(params) do
    data =
      Map.new(params, fn
        {key, value} when is_atom(key) -> {Atom.to_string(key), value}
        {key, value} -> {key, value}
      end)

    parse_page_json(Jason.encode!(data))
  end

  @doc """
  Parses JSON returned from the browser extraction script.
  """
  def parse_page_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{"blocked" => true} = data} ->
        {:error, {:blocked, Map.get(data, "summary", "USPS blocked automated access")}}

      {:ok, %{"not_found" => true} = data} ->
        {:error, {:not_found, page_debug(data)}}

      {:ok, data} when is_map(data) ->
        text = Map.get(data, "text", "")
        timed_out? = data["timeout"] == true

        cond do
          tracking_page?(text) ->
            {:ok,
             %{
               delivery_status: delivery_status_from_text(text),
               summary: summary_from_page(data, text)
             }}

          timed_out? ->
            {:error, {:page_timeout, page_debug(data)}}

          true ->
            {:error, {:not_found, page_debug(data)}}
        end

      {:error, _} ->
        snippet = json |> String.replace(~r/\s+/, " ") |> String.trim() |> String.slice(0, 180)
        {:error, {:parse_failed, "Response was not JSON: #{snippet}"}}
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

  @doc """
  Human-readable explanation for a tracking lookup error.
  """
  def error_message(reason) do
    case reason do
      :invalid_tracking_number ->
        "Tracking number is invalid"

      :no_tracking_number ->
        "Save a tracking number first"

      :chromic_pdf_unavailable ->
        "Chrome/Chromium is not available. Install Google Chrome to enable automatic tracking checks."

      :chromic_pdf_not_started ->
        "Chrome is not running. Restart the server after installing Google Chrome or Chromium."

      :lookup_failed ->
        "Tracking lookup failed unexpectedly. Try again or use View on USPS.com."

      {:lookup_failed, msg} when is_binary(msg) ->
        "Tracking lookup failed unexpectedly: #{msg}"

      {:chromic_pdf, msg} when is_binary(msg) ->
        condensed =
          msg
          |> String.split("Current protocol:")
          |> hd()
          |> String.replace(~r/\s+/, " ")
          |> String.trim()

        cond do
          String.contains?(msg, "Could not find session pool") ->
            "Tracking is not configured yet. Restart the server after updating, then try again."

          String.contains?(msg, "Timeout in Channel.run_protocol") ->
            "Chrome timed out waiting for USPS.com (45 seconds). The page may still be loading or blocking automated access. Use View on USPS.com to check manually, then try again."

          String.length(condensed) > 280 ->
            "Chrome could not load the USPS page: #{String.slice(condensed, 0, 280)}…"

          true ->
            "Chrome could not load the USPS page: #{condensed}"
        end

      :blocked ->
        "USPS blocked the automated lookup. Use View on USPS.com to check status manually."

      {:blocked, msg} when is_binary(msg) ->
        "USPS blocked the automated lookup: #{msg}. Use View on USPS.com to check status manually."

      :not_found ->
        "USPS has no record for that tracking number yet"

      {:not_found, msg} when is_binary(msg) ->
        "USPS has no record for that tracking number yet. #{msg}"

      :parse_failed ->
        "Could not parse the USPS tracking page"

      {:parse_failed, msg} when is_binary(msg) ->
        "Could not parse the USPS tracking page: #{msg}"

      :page_timeout ->
        "USPS page did not finish loading in time. Try again or use View on USPS.com."

      {:page_timeout, msg} when is_binary(msg) ->
        "USPS page did not finish loading in time. #{msg}"

      :helper_timeout ->
        "The browser helper did not send tracking status in time. Install it from Settings, keep the USPS tab open, then try again."

      :not_pending ->
        "No tracking refresh is waiting for this number. Click Refresh status, then keep the USPS tab open."

      :case_not_found ->
        "That case is no longer available"

      {:http_error, status} ->
        "USPS tracking lookup failed (HTTP #{status})"

      %Ecto.Changeset{} = changeset ->
        changeset.errors
        |> Enum.map(fn {field, {msg, _}} -> "#{field} #{msg}" end)
        |> Enum.join(", ")
        |> case do
          "" -> "Could not save tracking status"
          message -> message
        end

      other ->
        "Could not refresh tracking status (#{inspect(other)})"
    end
  end

  defp lookup_number(number, on_step) do
    emit_progress(on_step, :chrome, :running, "Checking whether Chrome can open USPS.com")

    case ensure_browser() do
      {:ok, chrome_detail} ->
        emit_progress(on_step, :chrome, :ok, chrome_detail)
        fetch_and_parse(number, on_step)

      {:error, reason} = error ->
        emit_progress(on_step, :chrome, :error, error_message(reason))
        error
    end
  end

  defp fetch_and_parse(number, on_step) do
    url = tracking_url(number)

    emit_progress(
      on_step,
      :fetch,
      :running,
      "Opening #{url} (this can take up to 45 seconds)"
    )

    started = System.monotonic_time(:millisecond)

    case page_fetcher().fetch(url) do
      {:ok, page_json} ->
        emit_progress(on_step, :fetch, :ok, "Page loaded in #{format_duration(started)}")
        parse_lookup_result(page_json, on_step)

      {:error, reason} = error ->
        emit_progress(on_step, :fetch, :error, error_message(reason))
        error
    end
  end

  defp parse_lookup_result(page_json, on_step) do
    emit_progress(on_step, :parse, :running, "Reading delivery status from the page")

    case parse_page_json(page_json) do
      {:ok, parsed} ->
        emit_progress(on_step, :parse, :ok, parsed.summary)

        {:ok,
         Map.merge(parsed, %{
           checked_at: DateTime.utc_now() |> DateTime.truncate(:second)
         })}

      {:error, reason} = error ->
        emit_progress(on_step, :parse, :error, error_message(reason))
        error
    end
  end

  defp ensure_browser do
    if page_fetcher() == PageFetcher do
      case LetterPdf.ensure_chromic_pdf!() do
        :ok -> {:ok, "Chrome is ready"}
        {:error, _} = error -> error
      end
    else
      {:ok, "Using configured page fetcher"}
    end
  end

  defp format_duration(started_ms) do
    elapsed = System.monotonic_time(:millisecond) - started_ms

    if elapsed < 1000 do
      "#{elapsed}ms"
    else
      "#{Float.round(elapsed / 1000, 1)}s"
    end
  end

  defp page_debug(data) when is_map(data) do
    title = blank_to_label(data["title"], "no title")
    url = blank_to_label(data["url"], "no url")
    ready = blank_to_label(to_string(data["readyState"] || ""), "unknown")
    html_length = data["htmlLength"] || 0
    iframe_count = data["iframeCount"] || 0

    snippet =
      (data["text"] || data["summary"] || data["html"] || "")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()
      |> String.slice(0, 180)

    text_part =
      if snippet == "" do
        "Page had no text (HTML #{html_length} chars, #{iframe_count} iframe(s), readyState=#{ready})."
      else
        "Page text: #{snippet}"
      end

    "Page title: #{title}. URL: #{url}. #{text_part}"
  end

  defp blank_to_label(value, fallback) when is_binary(value) do
    case String.trim(value) do
      "" -> fallback
      trimmed -> trimmed
    end
  end

  defp blank_to_label(_, fallback), do: fallback

  defp page_fetcher do
    config()[:page_fetcher] || PageFetcher
  end

  defp config, do: Application.get_env(:dnc_watchdog, :usps_tracking, [])

  defp summary_from_page(data, text) do
    [data["summary"], status_snippet(text), extract_summary(text)]
    |> Enum.find_value(fn candidate ->
      if usable_summary?(candidate), do: String.trim(candidate)
    end)
    |> case do
      nil -> status_snippet(text)
      summary -> summary
    end
  end

  defp usable_summary?(value) when is_binary(value) do
    trimmed = String.trim(value)
    trimmed != "" and not chrome_text?(trimmed)
  end

  defp usable_summary?(_), do: false

  defp extract_summary(text) do
    text
    |> candidate_lines()
    |> Enum.find_value("", fn line ->
      line_lc = String.downcase(line)

      if String.length(line) >= 12 and
           (delivered_status?(line_lc) or
              String.contains?(line_lc, "out for delivery") or
              String.contains?(line_lc, "in transit") or
              String.contains?(line_lc, "returned") or
              String.contains?(line_lc, "refused") or
              String.contains?(line_lc, "accepted") or
              String.contains?(line_lc, "departed") or
              String.contains?(line_lc, "label created") or
              String.contains?(line_lc, "pre-shipment") or
              String.contains?(line_lc, "available for pickup") or
              String.contains?(line_lc, "moving through the network")) do
        line
      end
    end)
  end

  defp candidate_lines(text) do
    text
    |> String.replace(~r/(?<=[.!?])\s+/, "\n")
    |> String.split(~r/[\n\r]+/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or chrome_text?(&1)))
  end

  defp status_snippet(text) when is_binary(text) do
    cleaned = strip_usps_chrome(text)

    [
      ~r/your item was delivered.{0,140}/i,
      ~r/delivered,.{0,80}/i,
      ~r/out for delivery.{0,80}/i,
      ~r/in transit.{0,100}/i,
      ~r/moving through the network.{0,80}/i,
      ~r/label created.{0,80}/i,
      ~r/pre-?shipment.{0,80}/i,
      ~r/returned to sender.{0,80}/i,
      ~r/available for pickup.{0,80}/i
    ]
    |> Enum.find_value("", fn regex ->
      case Regex.run(regex, cleaned) do
        [match | _] -> match |> String.replace(~r/\s+/, " ") |> String.trim()
        _ -> nil
      end
    end)
  end

  defp delivery_status_from_text(text) do
    text_lc = strip_usps_chrome(text)

    cond do
      returned_status?(text_lc) ->
        "returned"

      delivered_status?(text_lc) ->
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
    text_lc = strip_usps_chrome(text)

    status_markers = [
      "tracking history",
      "status not available",
      "label created",
      "your item was delivered",
      "delivered,",
      "in transit",
      "out for delivery",
      "returned to sender",
      "moving through the network",
      "processed through"
    ]

    Enum.any?(status_markers, &String.contains?(text_lc, &1)) or delivered_status?(text_lc)
  end

  defp delivered_status?(text_lc) do
    Enum.any?(
      [
        "your item was delivered",
        "was delivered",
        "delivered,",
        "delivered to the",
        "delivered at ",
        "delivered in/at",
        "delivered, in/at"
      ],
      &String.contains?(text_lc, &1)
    )
  end

  defp strip_usps_chrome(text) when is_binary(text) do
    Enum.reduce(chrome_patterns(), String.downcase(text), fn pattern, acc ->
      String.replace(acc, pattern, " ")
    end)
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp chrome_patterns do
    [
      ~r/informed delivery/,
      ~r/skip to main content/,
      ~r/skip all category navigation(?: links)?/,
      ~r/skip quick tools(?: links)?/,
      ~r/current language:[^.]{0,80}/,
      ~r/register\s*\/\s*sign in/,
      ~r/track a package/,
      ~r/find usps/,
      ~r/see (?:your )?(?:incoming )?mail when it(?:'s| is) delivered/,
      ~r/when it(?:'s| is) delivered/,
      ~r/packages delivered daily/
    ]
  end

  defp chrome_text?(text) when is_binary(text) do
    line_lc = String.downcase(text)

    String.contains?(line_lc, "skip to main content") or
      String.contains?(line_lc, "skip all category") or
      String.contains?(line_lc, "informed delivery") or
      String.contains?(line_lc, "current language") or
      String.contains?(line_lc, "skip quick tools")
  end
end

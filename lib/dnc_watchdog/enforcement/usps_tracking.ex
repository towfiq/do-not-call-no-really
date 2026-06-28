defmodule DncWatchdog.Enforcement.UspsTracking do
  @moduledoc """
  Looks up USPS tracking status via the official Tracking API v3.

  Requires OAuth credentials from the [USPS developer portal](https://developers.usps.com/).
  Set `USPS_CLIENT_ID` and `USPS_CLIENT_SECRET` environment variables, or configure
  `:dnc_watchdog, :usps_tracking` in config.

  Without credentials, tracking numbers can still be saved and linked to the public
  USPS tracking page, but automatic status checks will return `{:error, :not_configured}`.
  """

  require Logger

  @delivery_statuses ~w(pending pre_shipment in_transit out_for_delivery delivered returned alert unknown)

  @doc """
  Returns true when USPS API credentials are configured.
  """
  def configured? do
    config()[:client_id] not in [nil, ""] and config()[:client_secret] not in [nil, ""]
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
      normalized -> "https://tools.usps.com/go/TrackConfirmAction?tLabels=#{normalized}"
    end
  end

  @doc """
  Looks up tracking status from USPS.

  Returns `{:ok, result}` where result contains:
    * `:delivery_status` — one of #{inspect(@delivery_statuses)}
    * `:summary` — human-readable status text from USPS
    * `:checked_at` — UTC datetime of the lookup

  Or `{:error, reason}` where reason may be `:not_configured`, `:invalid_tracking_number`,
  `:not_found`, or `{:http_error, status}`.
  """
  def lookup(tracking_number) do
    case normalize_tracking_number(tracking_number) do
      nil ->
        {:error, :invalid_tracking_number}

      number ->
        if configured?() do
          do_lookup(number)
        else
          {:error, :not_configured}
        end
    end
  end

  @doc """
  Parses a USPS Tracking API v3 JSON response into delivery status and summary.
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

  defp do_lookup(number) do
    with {:ok, token} <- fetch_access_token(),
         {:ok, body} <- fetch_tracking(number, token) do
      parsed = parse_response(body)

      {:ok,
       Map.merge(parsed, %{
         checked_at: DateTime.utc_now() |> DateTime.truncate(:second)
       })}
    end
  end

  defp fetch_access_token do
    case cached_token() do
      {:ok, token} ->
        {:ok, token}

      :miss ->
        request_access_token()
    end
  end

  defp cached_token do
    now = System.system_time(:second)

    case :persistent_term.get({__MODULE__, :token}, nil) do
      {token, expires_at} when expires_at > now + 30 ->
        {:ok, token}

      _ ->
        :miss
    end
  end

  defp request_access_token do
    url = api_base() <> "/oauth2/v3/token"

    body =
      Jason.encode!(%{
        client_id: config()[:client_id],
        client_secret: config()[:client_secret],
        grant_type: "client_credentials",
        scope: "tracking"
      })

    headers = [{"content-type", "application/json"}]

    case http_post(url, headers, body) do
      {:ok, 200, response_body} ->
        %{"access_token" => token, "expires_in" => expires_in} = Jason.decode!(response_body)
        expires_at = System.system_time(:second) + expires_in
        :persistent_term.put({__MODULE__, :token}, {token, expires_at})
        {:ok, token}

      {:ok, status, response_body} ->
        Logger.warning("[UspsTracking] token request failed status=#{status} body=#{response_body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("[UspsTracking] token request error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_tracking(number, token) do
    url = api_base() <> "/tracking/v3/tracking/#{number}?expand=DETAIL"
    headers = [{"authorization", "Bearer #{token}"}, {"accept", "application/json"}]

    case http_get(url, headers) do
      {:ok, 200, body} ->
        {:ok, Jason.decode!(body)}

      {:ok, 404, _body} ->
        {:error, :not_found}

      {:ok, status, body} ->
        Logger.warning("[UspsTracking] tracking lookup failed status=#{status} body=#{body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
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

  defp http_get(url, headers), do: http_client().get(url, headers)
  defp http_post(url, headers, body), do: http_client().post(url, headers, body)

  defp http_client do
    config()[:http_client] || DncWatchdog.Enforcement.UspsTracking.FinchClient
  end

  defp config, do: Application.get_env(:dnc_watchdog, :usps_tracking, [])

  defp api_base do
    config()[:api_base] || "https://apis.usps.com"
  end
end

defmodule DncWatchdog.Enforcement.UspsTracking.FinchClient do
  @moduledoc false

  @finch DncWatchdog.Finch

  def get(url, headers) do
    request = Finch.build(:get, url, headers)

    case Finch.request(request, @finch, receive_timeout: 15_000) do
      {:ok, %{status: status, body: body}} -> {:ok, status, body}
      {:error, reason} -> {:error, reason}
    end
  end

  def post(url, headers, body) do
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, @finch, receive_timeout: 15_000) do
      {:ok, %{status: status, body: body}} -> {:ok, status, body}
      {:error, reason} -> {:error, reason}
    end
  end
end

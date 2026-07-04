defmodule DncWatchdog.Enforcement.UspsTrackingTest do
  use ExUnit.Case, async: true

  alias DncWatchdog.Enforcement.UspsTracking

  describe "normalize_tracking_number/1" do
    test "strips spaces and dashes" do
      assert UspsTracking.normalize_tracking_number("9400 1118 9922 3197 4284 90") ==
               "9400111899223197428490"
    end

    test "returns nil for blank input" do
      assert UspsTracking.normalize_tracking_number("   ") == nil
      assert UspsTracking.normalize_tracking_number(nil) == nil
    end
  end

  describe "tracking_url/1" do
    test "builds USPS tracking page URL" do
      assert UspsTracking.tracking_url("9400 1118 9922 3197 4284 90") ==
               "https://tools.usps.com/go/TrackConfirmAction?qtc_tLabels1=9400111899223197428490"
    end
  end

  describe "parse_response/1" do
    test "detects delivered status" do
      body = %{
        "status" => "Delivered, In/At Mailbox",
        "statusCategory" => "Delivered",
        "statusSummary" => "Your item was delivered at 3:14 pm on June 1, 2026.",
        "trackingEvents" => [
          %{"eventType" => "Delivered, In/At Mailbox"}
        ]
      }

      assert UspsTracking.parse_response(body) == %{
               delivery_status: "delivered",
               summary: "Your item was delivered at 3:14 pm on June 1, 2026."
             }
    end

    test "detects returned to sender" do
      body = %{
        "status" => "Returned to Sender",
        "statusCategory" => "Alert",
        "statusSummary" => "We attempted to deliver your item but it was returned to sender.",
        "trackingEvents" => [
          %{"eventType" => "Returned to Sender"}
        ]
      }

      assert UspsTracking.parse_response(body).delivery_status == "returned"
    end

    test "detects refused delivery" do
      body = %{
        "status" => "Refused",
        "statusCategory" => "Alert",
        "statusSummary" => "Addressee refused delivery.",
        "trackingEvents" => [%{"eventType" => "Refused"}]
      }

      assert UspsTracking.parse_response(body).delivery_status == "returned"
    end

    test "detects in transit" do
      body = %{
        "status" => "USPS in possession of item",
        "statusCategory" => "Accepted",
        "statusSummary" => "USPS is now in possession of your item.",
        "trackingEvents" => [%{"eventType" => "USPS in possession of item"}]
      }

      assert UspsTracking.parse_response(body).delivery_status == "in_transit"
    end

    test "detects out for delivery" do
      body = %{
        "status" => "Out for Delivery",
        "statusCategory" => "In Transit",
        "statusSummary" => "Out for Delivery",
        "trackingEvents" => [%{"eventType" => "Out for Delivery"}]
      }

      assert UspsTracking.parse_response(body).delivery_status == "out_for_delivery"
    end
  end

  describe "parse_page_json/1" do
    test "detects delivered status from page text" do
      json =
        Jason.encode!(%{
          "blocked" => false,
          "text" =>
            "Tracking Number: 9400 1118 9922 3197 4284 90 Delivered, In/At Mailbox Your item was delivered at 3:14 pm on June 1, 2026.",
          "summary" => "Delivered, In/At Mailbox"
        })

      assert {:ok, parsed} = UspsTracking.parse_page_json(json)
      assert parsed.delivery_status == "delivered"
      assert parsed.summary =~ "Delivered"
    end

    test "detects returned status from page text" do
      json =
        Jason.encode!(%{
          "blocked" => false,
          "text" => "Returned to Sender We attempted to deliver your item but it was returned to sender."
        })

      assert {:ok, parsed} = UspsTracking.parse_page_json(json)
      assert parsed.delivery_status == "returned"
    end

    test "returns not_found when USPS reports no tracking information" do
      json =
        Jason.encode!(%{
          "blocked" => false,
          "not_found" => true,
          "text" => "Status Not Available"
        })

      assert {:error, :not_found} = UspsTracking.parse_page_json(json)
    end

    test "returns blocked when USPS denies access" do
      json =
        Jason.encode!(%{
          "blocked" => true,
          "text" => "Access Denied",
          "summary" => "USPS blocked automated access"
        })

      assert {:error, {:blocked, "USPS blocked automated access"}} =
               UspsTracking.parse_page_json(json)
    end
  end

  describe "lookup/1" do
    setup do
      previous = Application.get_env(:dnc_watchdog, :usps_tracking, [])

      Application.put_env(:dnc_watchdog, :usps_tracking,
        page_fetcher: DncWatchdog.Enforcement.UspsTracking.StubPageFetcher
      )

      on_exit(fn ->
        Application.put_env(:dnc_watchdog, :usps_tracking, previous)
      end)

      :ok
    end

    test "parses a fetched USPS page" do
      assert {:ok, result} = UspsTracking.lookup("9400111899223197428490")
      assert result.delivery_status == "delivered"
      assert result.summary =~ "delivered"
      assert result.checked_at != nil
    end
  end
end
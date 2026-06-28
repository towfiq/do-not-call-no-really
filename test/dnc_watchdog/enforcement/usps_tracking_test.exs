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
               "https://tools.usps.com/go/TrackConfirmAction?tLabels=9400111899223197428490"
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

  describe "lookup/1 without credentials" do
    setup do
      previous = Application.get_env(:dnc_watchdog, :usps_tracking, [])
      Application.put_env(:dnc_watchdog, :usps_tracking, [])

      on_exit(fn ->
        Application.put_env(:dnc_watchdog, :usps_tracking, previous)
        :persistent_term.erase({UspsTracking, :token})
      end)

      :ok
    end

    test "returns not_configured when API credentials are absent" do
      assert UspsTracking.lookup("9400111899223197428490") == {:error, :not_configured}
    end
  end
end

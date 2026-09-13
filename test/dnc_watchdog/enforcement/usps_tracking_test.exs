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
    test "does not treat USPS navigation chrome as a tracking result" do
      json =
        Jason.encode!(%{
          "blocked" => false,
          "text" =>
            "Skip to Main Content Current language: English English Español Chinese Locations Support Informed Delivery Register / Sign In Skip all category navigation links Skip Quick Tools Links Quick Tools Track a Package Informed Delivery Find USPS",
          "summary" =>
            "Skip to Main Content Current language: English English Español Chinese Locations Support Informed Delivery Register / Sign In Skip all category navigation links Skip Quick Tools Links Quick Tools Track a Package Informed Delivery Find USPS"
        })

      assert {:error, {:not_found, _detail}} = UspsTracking.parse_page_json(json)
    end

    test "does not treat Informed Delivery marketing as delivered" do
      json =
        Jason.encode!(%{
          "blocked" => false,
          "text" =>
            "Skip all category navigation Informed Delivery See your mail when it's delivered. In transit to the destination. Moving through the network.",
          "summary" => "Skip all category navigation Informed Delivery"
        })

      assert {:ok, parsed} = UspsTracking.parse_page_json(json)
      assert parsed.delivery_status == "in_transit"
      assert parsed.summary =~ ~r/in transit/i
      refute parsed.summary =~ ~r/skip to main content|informed delivery/i
    end

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
          "text" =>
            "Returned to Sender We attempted to deliver your item but it was returned to sender."
        })

      assert {:ok, parsed} = UspsTracking.parse_page_json(json)
      assert parsed.delivery_status == "returned"
    end

    test "returns not_found when USPS reports no tracking information" do
      json =
        Jason.encode!(%{
          "blocked" => false,
          "not_found" => true,
          "text" => "Status Not Available",
          "title" => "USPS.com® - USPS Tracking®",
          "url" => "https://tools.usps.com/go/TrackConfirmAction"
        })

      assert {:error, {:not_found, detail}} = UspsTracking.parse_page_json(json)
      assert detail =~ "Status Not Available"
      assert detail =~ "USPS.com"
    end

    test "returns page_timeout when the USPS page never shows tracking status" do
      json =
        Jason.encode!(%{
          "blocked" => false,
          "timeout" => true,
          "text" => "Skip all category navigation Please wait",
          "title" => "Access Denied",
          "url" => "https://tools.usps.com/go/TrackConfirmAction"
        })

      assert {:error, {:page_timeout, detail}} = UspsTracking.parse_page_json(json)
      assert detail =~ "Access Denied"
    end

    test "includes HTML debug details when the page has no text" do
      json =
        Jason.encode!(%{
          "blocked" => false,
          "timeout" => true,
          "text" => "",
          "title" => "",
          "url" => "https://tools.usps.com/tracking/",
          "readyState" => "complete",
          "htmlLength" => 42,
          "iframeCount" => 1,
          "html" => "<html><body></body></html>"
        })

      assert {:error, {:page_timeout, detail}} = UspsTracking.parse_page_json(json)
      assert detail =~ "HTML 42 chars"
      assert detail =~ "1 iframe"
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

    test "emits progress steps for a successful lookup" do
      {:ok, agent} = Agent.start_link(fn -> [] end)
      on_step = fn step -> Agent.update(agent, &[step | &1]) end

      assert {:ok, _result} =
               UspsTracking.lookup("9400111899223197428490", on_step: on_step)

      steps = Agent.get(agent, &Enum.reverse/1)
      statuses = Enum.map(steps, &{&1.id, &1.status})

      assert {:validate, :running} in statuses
      assert {:validate, :ok} in statuses
      assert {:chrome, :ok} in statuses
      assert {:fetch, :ok} in statuses
      assert {:parse, :ok} in statuses
      refute Enum.any?(statuses, fn {id, _status} -> id == :save end)
    end

    test "error_message explains blocked lookups" do
      assert UspsTracking.error_message({:blocked, "USPS blocked automated access"}) =~
               "USPS blocked"
    end

    test "error_message condenses Chrome protocol timeouts" do
      message =
        UspsTracking.error_message(
          {:chromic_pdf,
           "Timeout in Channel.run_protocol/3!\n\nCurrent protocol:\n%ChromicPDF.Protocol{steps: []}"}
        )

      assert message =~ "timed out waiting for USPS.com"
      refute message =~ "Current protocol"
    end
  end

  describe "progress_steps/1" do
    test "browser helper steps wait for the extension" do
      ids = Enum.map(UspsTracking.progress_steps(:browser_helper), & &1.id)
      assert ids == [:validate, :open_browser, :wait_helper, :parse, :save]
    end
  end

  describe "parse_helper_payload/1" do
    test "parses a delivered helper page" do
      assert {:ok, parsed} =
               UspsTracking.parse_helper_payload(%{
                 "text" => "Tracking History Your item was delivered, May 1, 2026 at 3:14 pm.",
                 "summary" => "Your item was delivered, May 1, 2026 at 3:14 pm.",
                 "title" => "USPS Tracking",
                 "url" => "https://tools.usps.com/go/TrackConfirmAction?qtc_tLabels1=1"
               })

      assert parsed.delivery_status == "delivered"
      assert parsed.summary =~ "delivered"
    end
  end
end

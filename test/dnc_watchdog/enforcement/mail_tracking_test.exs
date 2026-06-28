defmodule DncWatchdog.Enforcement.MailTrackingTest do
  use DncWatchdog.DataCase, async: true

  alias DncWatchdog.Enforcement

  import DncWatchdog.EnforcementFixtures

  describe "save_mail_tracking_number/2" do
    test "normalizes and saves tracking number with pending status" do
      case = case_fixture()

      assert {:ok, updated} =
               Enforcement.save_mail_tracking_number(case, "9400 1118 9922 3197 4284 90")

      assert updated.mail_tracking_number == "9400111899223197428490"
      assert updated.mail_delivery_status == "pending"
      assert updated.mail_tracking_summary == nil
      assert updated.mail_tracking_checked_at == nil
    end

    test "clears tracking fields when number is blank" do
      case =
        case_fixture()
        |> then(fn c ->
          {:ok, c} =
            Enforcement.save_mail_tracking_number(c, "9400111899223197428490")

          c
        end)

      assert {:ok, cleared} = Enforcement.save_mail_tracking_number(case, "  ")
      assert cleared.mail_tracking_number == nil
      assert cleared.mail_delivery_status == nil
    end
  end

  describe "refresh_mail_tracking/1" do
    setup do
      previous = Application.get_env(:dnc_watchdog, :usps_tracking, [])

      Application.put_env(:dnc_watchdog, :usps_tracking,
        client_id: "test-id",
        client_secret: "test-secret",
        http_client: DncWatchdog.Enforcement.UspsTracking.StubClient
      )

      on_exit(fn ->
        Application.put_env(:dnc_watchdog, :usps_tracking, previous)
        :persistent_term.erase({DncWatchdog.Enforcement.UspsTracking, :token})
      end)

      :ok
    end

    test "updates case from USPS lookup" do
      case =
        case_fixture()
        |> then(fn c ->
          {:ok, c} = Enforcement.save_mail_tracking_number(c, "9400111899223197428490")
          c
        end)

      assert {:ok, updated} = Enforcement.refresh_mail_tracking(case)
      assert updated.mail_delivery_status == "delivered"
      assert updated.mail_tracking_summary =~ "delivered"
      assert updated.mail_tracking_checked_at != nil
    end

    test "returns not_configured without credentials" do
      Application.put_env(:dnc_watchdog, :usps_tracking, [])

      case =
        case_fixture()
        |> then(fn c ->
          {:ok, c} = Enforcement.save_mail_tracking_number(c, "9400111899223197428490")
          c
        end)

      assert {:error, :not_configured} = Enforcement.refresh_mail_tracking(case)
    end
  end
end

defmodule DncWatchdog.Enforcement.UspsTracking.StubClient do
  @moduledoc false

  def get(_url, _headers) do
    body =
      Jason.encode!(%{
        "status" => "Delivered, In/At Mailbox",
        "statusCategory" => "Delivered",
        "statusSummary" => "Your item was delivered at 3:14 pm on June 1, 2026.",
        "trackingEvents" => [%{"eventType" => "Delivered, In/At Mailbox"}]
      })

    {:ok, 200, body}
  end

  def post(_url, _headers, _body) do
    {:ok, 200, Jason.encode!(%{"access_token" => "stub-token", "expires_in" => 3600})}
  end
end

defmodule DncWatchdog.Enforcement.MailTrackingTest do
  use DncWatchdog.DataCase, async: false

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
        page_fetcher: DncWatchdog.Enforcement.UspsTracking.StubPageFetcher
      )

      on_exit(fn ->
        Application.put_env(:dnc_watchdog, :usps_tracking, previous)
      end)

      :ok
    end

    test "updates case from parsed USPS page" do
      case =
        case_fixture(%{workflow_step: "sent", status: "sent"})
        |> then(fn c ->
          {:ok, c} = Enforcement.save_mail_tracking_number(c, "9400111899223197428490")
          c
        end)

      assert {:ok, updated} = Enforcement.refresh_mail_tracking(case)
      assert updated.mail_delivery_status == "delivered"
      assert updated.mail_tracking_summary =~ "delivered"
      assert updated.mail_tracking_checked_at != nil
      assert updated.workflow_step == "delivered"
      assert updated.status == "delivered"
    end

    test "does not change workflow when case is not at sent" do
      case =
        case_fixture(%{workflow_step: "ready_to_send", status: "investigating"})
        |> then(fn c ->
          {:ok, c} = Enforcement.save_mail_tracking_number(c, "9400111899223197428490")
          c
        end)

      assert {:ok, updated} = Enforcement.refresh_mail_tracking(case)
      assert updated.mail_delivery_status == "delivered"
      assert updated.workflow_step == "ready_to_send"
      assert updated.status == "investigating"
    end
  end
end

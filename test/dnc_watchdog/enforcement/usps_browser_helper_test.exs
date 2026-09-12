defmodule DncWatchdog.Enforcement.UspsBrowserHelperTest do
  use ExUnit.Case, async: false

  alias DncWatchdog.Enforcement.UspsBrowserHelper

  setup do
    UspsBrowserHelper.reset()
    :ok
  end

  test "take consumes a registered lookup" do
    assert :ok = UspsBrowserHelper.register("9400111899223197428490", 12)
    assert {:ok, %{case_id: 12}} = UspsBrowserHelper.take("9400111899223197428490")
    assert {:error, :not_pending} = UspsBrowserHelper.take("9400111899223197428490")
  end

  test "expired lookups are not taken" do
    assert :ok = UspsBrowserHelper.register("9400111899223197428490", 12, ttl_ms: 0)
    Process.sleep(1)
    assert {:error, :not_pending} = UspsBrowserHelper.take("9400111899223197428490")
  end

  test "cancel drops a pending lookup" do
    assert :ok = UspsBrowserHelper.register("9400111899223197428490", 12)
    assert :ok = UspsBrowserHelper.cancel("9400111899223197428490")
    assert {:error, :not_pending} = UspsBrowserHelper.take("9400111899223197428490")
  end

  test "extension_dir points at the unpacked Chrome helper" do
    dir = UspsBrowserHelper.extension_dir()
    assert File.exists?(Path.join(dir, "manifest.json"))
    assert File.exists?(Path.join(dir, "content.js"))
  end
end

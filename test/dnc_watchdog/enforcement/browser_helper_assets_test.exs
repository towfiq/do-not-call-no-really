defmodule DncWatchdog.Enforcement.BrowserHelperAssetsTest do
  use ExUnit.Case, async: true

  test "Safari manifest includes the eFileCA filler and Tyler hosts" do
    manifest =
      "priv/safari_extension/DNCWatchdogUspsHelper/DNCWatchdogUspsHelper Extension/manifest.json"
      |> File.read!()
      |> Jason.decode!()

    assert manifest["version"] == "1.3.0"
    assert "https://california.tylertech.cloud/*" in manifest["host_permissions"]
    assert "http://127.0.0.1/*" in manifest["host_permissions"]

    matches = Enum.flat_map(manifest["content_scripts"], & &1["matches"])
    refute Enum.any?(matches, &String.contains?(&1, ":4000"))
    assert "http://127.0.0.1/*" in matches
    assert manifest["background"]["scripts"] == ["background.js"]

    scripts =
      manifest["content_scripts"]
      |> Enum.flat_map(& &1["js"])

    assert "efile_fill.js" in scripts
    assert "app_bridge.js" in scripts
  end

  test "Chrome and Safari helpers ship the same version" do
    version = fn path -> path |> File.read!() |> Jason.decode!() |> Map.fetch!("version") end
    flag = File.read!("priv/chrome_extension/page_flag.js")

    chrome = version.("priv/chrome_extension/manifest.json")

    safari =
      version.(
        "priv/safari_extension/DNCWatchdogUspsHelper/DNCWatchdogUspsHelper Extension/manifest.json"
      )

    assert chrome == safari
    # The page flag is how the app decides whether a helper is installed.
    assert flag =~ "version: \"#{chrome}\""
  end

  test "eFile filler routes on the wizard step in the URL" do
    source = File.read!("priv/chrome_extension/efile_fill.js")

    assert source =~ "function currentStep()"
    # The dashboard button is "Start Filing"; "Start New Case" is a page later.
    assert source =~ "start-filing"
    assert source =~ "case-information"
    assert source =~ "async function fillParties(data)"
    assert source =~ "async function fillFilings(data)"
    assert source =~ "function onSignIn()"
  end

  test "eFile filler drives Forge comboboxes rather than selects" do
    source = File.read!("priv/chrome_extension/efile_fill.js")

    # Forge autocompletes only render options after focus plus ArrowDown, and
    # each input owns its popup via aria-controls.
    assert source =~ "key: \"ArrowDown\""
    assert source =~ "getAttribute(\"aria-controls\")"
    assert source =~ "[role='option']"
    # Court labels mix hyphens and en dashes ("Santa Clara – Civil").
    assert source =~ "\\u2010-\\u2015"
  end

  test "eFile filler waits for Forge buttons to become enabled" do
    source = File.read!("priv/chrome_extension/efile_fill.js")

    assert source =~ "async function clickWhenEnabled("
    assert source =~ "getAttribute(\"aria-disabled\") === \"true\""
    # Saved party rows swap "Add party details" for an Edit party icon button.
    assert source =~ "[aria-label='Edit party']"
    assert source =~ "forge-button-toggle"
  end

  test "eFile filler uploads through the file picker's shadow input" do
    filler = File.read!("priv/chrome_extension/efile_fill.js")
    background = File.read!("priv/chrome_extension/background.js")

    assert filler =~ "forge-file-picker"
    assert filler =~ "shadowRoot?.querySelector('input[type=\"file\"]')"
    assert filler =~ "new DataTransfer()"
    assert filler =~ "input.files = transfer.files"
    # One lead document per filing, so the lead form goes first.
    assert filler =~ "Number(isLead(b)) - Number(isLead(a))"
    assert filler =~ "save-filings"
    assert filler =~ "type: \"fetchDocument\""

    assert background =~ "message?.type === \"fetchDocument\""
    assert background =~ "async function fetchDocument(url)"
  end

  test "eFile filler will not add the same form twice after a reload" do
    source = File.read!("priv/chrome_extension/efile_fill.js")

    # A reload empties FILLED, so the saved filings table is the real record.
    assert source =~ "function alreadyFiled(doc)"
    assert source =~ "docs.find((entry) => !alreadyFiled(entry))"
    assert source =~ "function leadFirst(documents)"
  end

  test "the filler still refuses to submit or pay" do
    source = File.read!("priv/chrome_extension/efile_fill.js")

    assert source =~ "FORBIDDEN_CLICK"
    # Service, Fees, and Summary are terminal: the helper only reports there.
    assert source =~ "Ready for your review"
    refute source =~ "skip-to-fees"
  end

  test "helper failures reach the app instead of failing silently" do
    bridge = File.read!("priv/chrome_extension/app_bridge.js")
    background = File.read!("priv/chrome_extension/background.js")
    app_js = File.read!("assets/js/app.js")

    assert bridge =~ "dnc-efile-helper-error"
    assert background =~ "the filler never loaded on the eFileCA tab"
    assert app_js =~ "pushEvent(\"efile_helper_error\""
    # The portal tab opens even when the helper is wedged.
    assert app_js =~ "window.open(portal_url, \"dnc-efileca\")"
    refute app_js =~ "if (!window.__DNC_USPS_HELPER__) {"
  end

  test "blank Judicial Council of California forms ship with the app" do
    for file <- ["sc100.pdf", "sum100.pdf", "cm010.pdf", "pos010.pdf"] do
      path = Path.join("priv/judicial_forms", file)
      assert File.exists?(path), "missing #{path} — run mix dnc.setup_forms"
      assert <<"%PDF", _::binary>> = File.read!(path)
    end
  end

  test "Safari Xcode project copies efile_fill.js from the Chrome helper" do
    pbx =
      File.read!(
        "priv/safari_extension/DNCWatchdogUspsHelper/DNCWatchdogUspsHelper.xcodeproj/project.pbxproj"
      )

    assert pbx =~ "efile_fill.js"
    assert pbx =~ "../../../chrome_extension/efile_fill.js"
  end
end

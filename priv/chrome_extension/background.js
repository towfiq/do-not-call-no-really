const ext = globalThis.browser ?? globalThis.chrome;
const DEFAULT_ORIGIN = "http://127.0.0.1:4000";
const USPS_TAB_QUERY = ["https://tools.usps.com/*", "https://www.usps.com/*"];

ext.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "setAppOrigin" && typeof message.origin === "string") {
    ext.storage.local.set({appOrigin: message.origin});
    sendResponse({ok: true});
    return;
  }

  if (message?.type === "uspsPage") {
    postStatus(message.payload)
      .then((result) => sendResponse(result))
      .catch((error) => sendResponse({ok: false, error: String(error)}));
    return true;
  }

  if (message?.type === "captureTracking") {
    captureTracking(message)
      .then((result) => sendResponse(result))
      .catch((error) => sendResponse({ok: false, error: String(error)}));
    return true;
  }
});

async function captureTracking({url, tracking_number}) {
  const tab = await findOrOpenUspsTab(url, tracking_number);
  await waitForTabLoad(tab.id);
  await askTabToExtract(tab.id, tracking_number);
  return {ok: true, tabId: tab.id};
}

async function findOrOpenUspsTab(url, tracking_number) {
  const tabs = await ext.tabs.query({url: USPS_TAB_QUERY});
  const match =
    tabs.find((tab) => tracking_number && (tab.url || "").includes(tracking_number)) ||
    tabs.find((tab) => tab.url && /tools\.usps\.com|usps\.com/.test(tab.url));

  if (match) {
    if (tracking_number && (match.url || "").includes(tracking_number)) {
      await ext.tabs.update(match.id, {active: true});
      await ext.tabs.reload(match.id);
    } else {
      await ext.tabs.update(match.id, {active: true, url});
    }
    return match;
  }

  return ext.tabs.create({url, active: true});
}

function waitForTabLoad(tabId) {
  return new Promise((resolve) => {
    let sawLoading = false;

    const finish = () => {
      ext.tabs.onUpdated.removeListener(onUpdated);
      resolve();
    };

    const timeout = setTimeout(finish, 15000);

    const onUpdated = (id, info) => {
      if (id !== tabId) return;
      if (info.status === "loading") sawLoading = true;
      if (info.status === "complete" && sawLoading) {
        clearTimeout(timeout);
        finish();
      }
    };

    ext.tabs.onUpdated.addListener(onUpdated);
  });
}

async function askTabToExtract(tabId, tracking_number) {
  for (let attempt = 0; attempt < 10; attempt += 1) {
    try {
      await ext.tabs.sendMessage(tabId, {type: "extractNow", tracking_number});
      return;
    } catch (_err) {
      if (attempt === 0 || attempt === 4) {
        try {
          await ext.scripting.executeScript({
            target: {tabId},
            files: ["content.js"]
          });
        } catch (_injectErr) {}
      }
      await sleep(400);
    }
  }
}

async function postStatus(payload) {
  const origin = await appOrigin();
  let lastError = "Failed to fetch";

  for (let attempt = 0; attempt < 6; attempt += 1) {
    try {
      const response = await fetch(`${origin}/api/usps_helper`, {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(payload)
      });
      const body = await response.json().catch(() => ({}));

      if (response.ok || response.status !== 409) {
        return {ok: response.ok, status: response.status, body};
      }

      lastError = body.error || "no_pending_lookup";
    } catch (error) {
      lastError = String(error);
    }

    await sleep(500);
  }

  return {ok: false, error: lastError};
}

async function appOrigin() {
  const stored = await ext.storage.local.get("appOrigin");
  return stored.appOrigin || DEFAULT_ORIGIN;
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

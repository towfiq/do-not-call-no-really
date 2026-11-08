(() => {
  const ext = globalThis.browser ?? globalThis.chrome;

  // The app's CSP is script-src 'self', so an injected page_flag.js from
  // chrome-extension:// or safari-web-extension:// never runs and the case
  // page treats the helper as missing. A DOM attribute is shared with the
  // page and is not subject to that policy.
  const announce = () => {
    const root = document.documentElement;
    if (!root) return false;
    const version = ext.runtime.getManifest?.().version;
    if (version) root.dataset.dncUspsHelper = version;
    window.dispatchEvent(new CustomEvent("dnc-usps-helper-ready"));
    return true;
  };

  if (!announce()) {
    document.addEventListener("DOMContentLoaded", announce, {once: true});
  }

  try {
    const script = document.createElement("script");
    script.src = ext.runtime.getURL("page_flag.js");
    script.onload = () => script.remove();
    (document.head || document.documentElement).appendChild(script);
  } catch (_err) {}

  window.addEventListener("dnc-usps-helper-open", (event) => {
    const detail = event.detail || {};
    const sending = ext.runtime.sendMessage({
      type: "captureTracking",
      url: detail.url,
      tracking_number: detail.tracking_number
    });
    if (sending && typeof sending.catch === "function") sending.catch(() => {});
  });

  // Report failures back to the page: a silent helper is indistinguishable from
  // a dead button, which is the worst way for this to break.
  const reportError = (message) => {
    window.dispatchEvent(new CustomEvent("dnc-efile-helper-error", {detail: String(message)}));
  };

  window.addEventListener("dnc-efile-helper-open", (event) => {
    const detail = event.detail || {};
    const sending = ext.runtime.sendMessage({
      type: "fillEfile",
      case_id: detail.case_id,
      portal_url: detail.portal_url
    });
    if (sending && typeof sending.then === "function") {
      sending.then(
        (result) => {
          if (result && result.ok === false) reportError(result.error || "helper failed");
        },
        (error) => reportError(error)
      );
    }
  });

  try {
    ext.runtime.sendMessage({
      type: "setAppOrigin",
      origin: window.location.origin
    });
  } catch (_err) {}
})();

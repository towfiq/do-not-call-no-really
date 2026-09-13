(() => {
  const ext = globalThis.browser ?? globalThis.chrome;
  const script = document.createElement("script");
  script.src = ext.runtime.getURL("page_flag.js");
  script.onload = () => script.remove();
  (document.head || document.documentElement).appendChild(script);

  window.addEventListener("dnc-usps-helper-open", (event) => {
    const detail = event.detail || {};
    const sending = ext.runtime.sendMessage({
      type: "captureTracking",
      url: detail.url,
      tracking_number: detail.tracking_number
    });
    if (sending && typeof sending.catch === "function") sending.catch(() => {});
  });

  try {
    ext.runtime.sendMessage({
      type: "setAppOrigin",
      origin: window.location.origin
    });
  } catch (_err) {}
})();

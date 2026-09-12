(() => {
  const script = document.createElement("script");
  script.src = chrome.runtime.getURL("page_flag.js");
  script.onload = () => script.remove();
  (document.head || document.documentElement).appendChild(script);

  window.addEventListener("dnc-usps-helper-open", (event) => {
    const detail = event.detail || {};
    chrome.runtime.sendMessage({
      type: "captureTracking",
      url: detail.url,
      tracking_number: detail.tracking_number
    });
  });

  try {
    chrome.runtime.sendMessage({
      type: "setAppOrigin",
      origin: window.location.origin
    });
  } catch (_err) {}
})();

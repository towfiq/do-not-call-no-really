(() => {
  const ext = globalThis.browser ?? globalThis.chrome;
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  let postedKey = null;
  let running = false;

  const STATUS_RE =
    /tracking history|your item was delivered|delivered,|out for delivery|label created|pre-shipment|in transit|returned to sender|available for pickup|moving through the network|status not available|not yet available|invalid tracking|no tracking information/i;

  const WIDGET_SELECTORS = [
    '[id*="trackingResult"]',
    '[id*="tracking-result"]',
    '[class*="tracking-result"]',
    '[class*="trackingResult"]',
    '[class*="tb-status"]',
    ".tb-status",
    ".tb-status-detail",
    "#tracked-numbers",
    '[class*="track-bar"]',
    '[class*="tracking-progress"]',
    '[class*="redesigned-tracking"]',
    "main",
    "#main",
    "#mainContent",
    '[role="main"]'
  ];

  const collectNodeText = (root) => {
    const parts = [];
    const visit = (node) => {
      if (!node) return;
      if (node.innerText) parts.push(node.innerText);
      const elements = node.querySelectorAll ? node.querySelectorAll("*") : [];
      for (const el of elements) {
        if (el.shadowRoot) visit(el.shadowRoot);
      }
    };
    visit(root);
    return parts.join(" ").replace(/\s+/g, " ").trim();
  };

  const stripChrome = (text) =>
    (text || "")
      .replace(/informed delivery/gi, " ")
      .replace(/skip to main content/gi, " ")
      .replace(/skip all category navigation(?: links)?/gi, " ")
      .replace(/skip quick tools(?: links)?/gi, " ")
      .replace(/current language:[^.]{0,80}/gi, " ")
      .replace(/register\s*\/\s*sign in/gi, " ")
      .replace(/track a package/gi, " ")
      .replace(/find usps/gi, " ")
      .replace(/\s+/g, " ")
      .trim();

  const collectWidgetText = () => {
    const chunks = [];
    for (const selector of WIDGET_SELECTORS) {
      for (const el of document.querySelectorAll(selector)) {
        if (el.closest('header, nav, footer, [role="banner"], [role="navigation"]')) continue;
        const text = collectNodeText(el);
        if (text) chunks.push(text);
      }
    }

    for (const el of document.querySelectorAll("h1, h2, h3, h4, p, span")) {
      const text = (el.innerText || "").replace(/\s+/g, " ").trim();
      if (text && STATUS_RE.test(text) && !/informed delivery/i.test(text)) {
        chunks.unshift(text);
      }
    }

    return [...new Set(chunks)].join(" ").replace(/\s+/g, " ").trim();
  };

  const trackingNumberFromPage = (preferred) => {
    const normalizedPreferred = (preferred || "").replace(/[^0-9A-Za-z]/g, "");
    if (normalizedPreferred.length >= 12) return normalizedPreferred;

    const params = new URLSearchParams(location.search);
    for (const key of ["qtc_tLabels1", "tLabels", "tLabels1", "label"]) {
      const value = (params.get(key) || "").replace(/[^0-9A-Za-z]/g, "");
      if (value.length >= 12) return value;
    }

    const match = collectNodeText(document.body).match(/\b([0-9A-Za-z]{12,34})\b/);
    return match ? match[1] : "";
  };

  const statusSnippet = (text) => {
    const cleaned = stripChrome(text);
    const patterns = [
      /your item was delivered.{0,140}/i,
      /delivered,.{0,80}/i,
      /out for delivery.{0,80}/i,
      /in transit.{0,100}/i,
      /moving through the network.{0,80}/i,
      /label created.{0,80}/i,
      /pre-shipment.{0,80}/i,
      /returned to sender.{0,80}/i,
      /available for pickup.{0,80}/i
    ];
    for (const pattern of patterns) {
      const match = cleaned.match(pattern);
      if (match) return match[0].replace(/\s+/g, " ").trim();
    }
    return "";
  };

  const snapshot = (preferredNumber, extra = {}) => {
    const widgetText = collectWidgetText();
    const pageText = collectNodeText(document.body);
    const text = stripChrome(widgetText || pageText);
    const html = document.documentElement?.outerHTML || "";
    const summary = statusSnippet(text) || text.slice(0, 240);
    return Object.assign(
      {
        tracking_number: trackingNumberFromPage(preferredNumber),
        blocked: /access denied/i.test(text) || /access denied/i.test(html),
        not_found: /status not available|not yet available|invalid tracking|no tracking information/i.test(
          text
        ),
        text,
        summary,
        url: location.href,
        title: document.title,
        readyState: document.readyState,
        htmlLength: html.length,
        iframeCount: document.querySelectorAll("iframe").length
      },
      extra
    );
  };

  const hasRealStatus = (payload) =>
    Boolean(payload.summary) &&
    STATUS_RE.test(payload.text) &&
    !/skip to main content|skip all category navigation/i.test(payload.summary);

  const postOnce = (payload) => {
    const key = `${payload.tracking_number}:${payload.timeout ? "timeout" : "ok"}:${payload.summary}`;
    if (!payload.tracking_number || postedKey === key) return;
    postedKey = key;
    const sending = ext.runtime.sendMessage({type: "uspsPage", payload});
    if (sending && typeof sending.catch === "function") sending.catch(() => {});
  };

  const tick = async (preferredNumber) => {
    if (running) return;
    running = true;
    postedKey = null;
    const deadline = Date.now() + 90000;

    try {
      while (Date.now() < deadline) {
        const payload = snapshot(preferredNumber);
        if (payload.tracking_number && (payload.blocked || payload.not_found || hasRealStatus(payload))) {
          postOnce(payload);
          return;
        }
        await sleep(400);
      }

      postOnce(snapshot(preferredNumber, {timeout: true}));
    } finally {
      running = false;
    }
  };

  ext.runtime.onMessage.addListener((message) => {
    if (message?.type === "extractNow") {
      tick(message.tracking_number);
    }
  });

  tick();
})();

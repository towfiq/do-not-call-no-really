(() => {
  const PANEL_ID = "dnc-efile-helper-panel";
  const FILLED = new Set();
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  let payload = null;
  let observer = null;
  let ticking = false;

  const ext = globalThis.browser ?? globalThis.chrome;

  // Odyssey eFileCA runs on Tyler's Forge web components. Buttons are custom
  // elements that carry role="button" on the host, and every dropdown is a
  // <forge-autocomplete> around <input role="combobox"> whose options only
  // render after the input is focused and ArrowDown is dispatched.
  const CLICKABLE =
    "button, a, [role='button'], [role='switch'], input[type='button'], input[type='submit']";

  const FORBIDDEN_CLICK =
    /\b(submit|pay now|checkout|submit envelope|submit filing|file now|purchase|authorize payment)\b/i;
  const START_FILING = /^\s*start filing\s*$/i;
  const START_NEW_CASE = /^\s*(start (a )?new case|file new case)\s*$/i;
  const SAVE = /^\s*(save|save changes|add|done|ok|apply)\s*$/i;
  const NEXT_PARTIES = /^\s*parties\s*$/i;
  const NEXT_FILINGS = /^\s*filings\s*$/i;

  ext.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message?.type === "efilePayload") {
      payload = message.payload;
      persistPayload(payload);
      ensurePanel();
      runFill()
        .then(() => sendResponse({ok: true}))
        .catch((error) => {
          log(String(error));
          sendResponse({ok: false, error: String(error)});
        });
      return true;
    }
  });

  function persistPayload(next) {
    try {
      sessionStorage.setItem("dncEfilePayload", JSON.stringify(next));
    } catch (_err) {}
  }

  function restorePayload() {
    if (payload) return payload;
    try {
      const raw = sessionStorage.getItem("dncEfilePayload");
      if (raw) payload = JSON.parse(raw);
    } catch (_err) {}
    return payload;
  }

  async function runFill() {
    const data = restorePayload();
    if (!data) return;
    ensurePanel();
    updatePanel();
    if (ticking) return;
    ticking = true;
    try {
      await fillPass(data);
    } finally {
      ticking = false;
    }
  }

  // The wizard keeps the step in the URL, which is far more reliable than
  // sniffing page copy: /ui/dashboard, /ui/start-filing, then
  // /ui/edit-envelope/<uuid>/<step>.
  function currentStep() {
    const path = location.pathname;
    if (/\/ui\/dashboard/.test(path)) return "dashboard";
    if (/\/ui\/start-filing/.test(path)) return "start-filing";
    const envelope = path.match(/\/ui\/edit-envelope\/[^/]+\/([^/?#]+)/);
    if (envelope) return envelope[1];
    return onSignIn() ? "sign-in" : "unknown";
  }

  async function fillPass(data) {
    switch (currentStep()) {
      case "sign-in":
        updatePanel("Sign in (or register as an Individual), then return to this tab.");
        return;
      case "dashboard":
        await enterWizard(START_FILING, "start-filing");
        return;
      case "start-filing":
        await enterWizard(START_NEW_CASE, "new-case");
        return;
      case "case-information":
        await fillCaseInformation(data);
        return;
      case "parties":
        await fillParties(data);
        return;
      case "filings":
        await fillFilings(data);
        return;
      case "service":
      case "fees":
      case "summary":
        updatePanel("Ready for your review — the helper stops before Submit.");
        return;
      default:
        updatePanel("Open a filing draft, or click Start Filing on the dashboard.");
    }
  }

  async function enterWizard(re, key) {
    const from = currentStep();
    if (await clickWhenEnabled(re, key)) await waitForStepChange(from);
  }

  async function fillCaseInformation(data) {
    await pickOption(["Court Location"], data.court?.location_hints, "case");
    await pickOption(["Case Category"], data.category_hints, "case");
    await pickOption(["Case Type"], data.case_type_hints, "case");
    if (await clickWhenEnabled(NEXT_PARTIES, "goto-parties")) {
      await waitForStepChange("case-information");
    }
  }

  async function fillParties(data) {
    for (const party of [data.plaintiff, data.defendant]) {
      if (!party || FILLED.has(`party:${party.role}`)) continue;
      if (!(await openPartyModal(party.role))) continue;

      await fillPartyModal(party, data);
      // Save/Cancel for the party form live outside the modal, in app-parties.
      if (await clickById("save-parties", `save:${party.role}`)) {
        FILLED.add(`party:${party.role}`);
        await waitForModalClose();
      }
      // One party per pass; the observer fires again for the next one.
      return;
    }

    if (await clickWhenEnabled(NEXT_FILINGS, "goto-filings")) {
      await waitForStepChange("parties");
    }
  }

  // A blank row offers "Add party details"; once saved it becomes an
  // "Edit party" icon button, and the helper has to reopen that on later passes.
  async function openPartyModal(role) {
    if (openModal()) return true;
    // Pick the tightest container mentioning this role: a wrapper holding both
    // rows would hand back the other party's button.
    const row = Array.from(document.querySelectorAll("tr, [class*='party']"))
      .filter((el) => new RegExp(role, "i").test(el.innerText || ""))
      .sort((a, b) => (a.innerText || "").length - (b.innerText || "").length)[0];
    if (!row) return false;

    const button =
      clickables(/^\s*add party details\s*$/i, row)[0] ||
      row.querySelector("[aria-label='Edit party']");
    if (!button || isDisabled(button)) return false;

    button.click();
    log(`Opened ${role} party details.`);
    return await waitFor(() => openModal());
  }

  async function fillPartyModal(party, data) {
    const scope = openModal() || document;
    // Person/Entity is a forge-button-toggle-group, not a checkbox.
    await selectPartyKind(party.is_business ? "Entity" : "Person", scope);
    if (party.is_this_party) await setSwitch(/i am this party/i, true, scope);

    if (party.is_business) {
      await setField(["Entity Name", "Organization Name", "Business Name"], party.organization_name, party.role);
    } else {
      await setField(["First Name"], party.first_name, party.role);
      await setField(["Last Name"], party.last_name, party.role);
    }

    await pickOption(["Country"], party.address?.country_hints, party.role);
    await setField(["Address Line 1", "Street Address"], party.address?.street, party.role);
    await setField(["City"], party.address?.city, party.role);
    await pickOption(["State"], stateHints(party.address), party.role);
    await setField(["Zip Code", "Postal Code"], party.address?.zip, party.role);
    await setField(["Phone Number"], party.phone, party.role);
    await pickOption(["Lead Attorney"], data.lead_attorney_hints, party.role);
  }

  function stateHints(address) {
    if (!address?.state) return [];
    return [address.state, STATE_NAMES[address.state.toUpperCase()]].filter(Boolean);
  }

  const STATE_NAMES = {CA: "California", NY: "New York", TX: "Texas", WA: "Washington", IL: "Illinois"};

  async function selectPartyKind(kind, scope) {
    const key = `kind:${kind}:${scope === document ? "page" : "modal"}`;
    if (FILLED.has(key)) return true;
    const toggle = Array.from(scope.querySelectorAll("forge-button-toggle")).find(
      (el) => norm(el.textContent) === norm(kind)
    );
    if (!toggle) return false;
    if (!toggle.hasAttribute("selected")) {
      toggle.click();
      await sleep(600);
    }
    FILLED.add(key);
    return true;
  }

  async function setSwitch(re, on, scope) {
    const control = Array.from((scope || document).querySelectorAll("[role='switch']")).find((el) =>
      re.test(el.textContent || el.getAttribute("aria-label") || "")
    );
    if (!control) return false;
    if ((control.getAttribute("aria-checked") === "true") !== Boolean(on)) {
      control.click();
      await sleep(600);
    }
    return true;
  }

  // Each filing holds exactly one lead document, so every form becomes its own
  // filing with its own filing code. One filing per pass; the observer returns.
  async function fillFilings(data) {
    const docs = leadFirst(data.documents);
    if (docs.length === 0) {
      updatePanel("Generate a filing draft first — there is nothing to attach.");
      return;
    }

    const doc = docs.find((entry) => !alreadyFiled(entry));
    if (!doc) {
      updatePanel("All court forms attached. Continue to Service, then review and submit yourself.");
      return;
    }

    if (!(await openFilingForm(doc))) {
      updatePanel(`Click Add Filing and the helper will attach ${doc.label}.`);
      return;
    }

    await pickOption(["Filing Code"], doc.filing_code_hints, `filing:${doc.url}`);
    await setField(["Filing Description"], doc.description, `filing:${doc.url}`);
    await setField(["Client Reference Number"], data.client_reference, `filing:${doc.url}`);
    if (isLead(doc)) {
      await setField(["Comments to Court"], data.comments_to_court, `filing:${doc.url}`);
    }

    const input = filePicker();
    if (!input) {
      updatePanel(`Upload ${doc.label} yourself — no upload field on this filing.`);
      return;
    }

    const file = await downloadDocument(doc);
    if (!file) return;
    if (!attachFile(input, file)) return;

    log(`Attached ${doc.label}${isLead(doc) ? " (lead document)" : ""}.`);
    await sleep(1200);

    if (await clickById("save-filings", `save-filing:${doc.url}`)) {
      FILLED.add(`filing:${doc.url}`);
      await sleep(1500);
    }
  }

  // A reload wipes the in-memory record, so also read what the page already
  // shows: the saved filings table lists each filing's description. Without
  // this the helper would add a second filing for the same form.
  function alreadyFiled(doc) {
    if (FILLED.has(`filing:${doc.url}`)) return true;
    if (!doc.description) return false;
    const table = document.querySelector("table");
    return Boolean(table && norm(table.innerText).includes(norm(doc.description)));
  }

  function leadFirst(documents) {
    return (documents || [])
      .filter((doc) => doc && doc.url)
      .sort((a, b) => Number(isLead(b)) - Number(isLead(a)));
  }

  function isLead(doc) {
    return Boolean(doc["lead?"] ?? doc.lead);
  }

  async function openFilingForm(doc) {
    if (filePicker()) return true;
    // "Add Filing" for the first filing, "Add More" for every one after it.
    for (const id of ["add-filing-initial", "add-filing"]) {
      if (await clickById(id, `${id}:${doc.url}`)) return await waitFor(() => filePicker());
    }
    return false;
  }

  // The upload control is a <forge-file-picker> whose real <input type="file">
  // sits in its shadow root, out of reach of a plain document query.
  function filePicker() {
    const pickers = Array.from(document.querySelectorAll("forge-file-picker"))
      .map((picker) => picker.shadowRoot?.querySelector('input[type="file"]'))
      .filter(Boolean);
    const light = Array.from(document.querySelectorAll('input[type="file"]'));
    return pickers.concat(light).find((input) => input.dataset.dncUsed !== "1" && !input.disabled);
  }

  async function downloadDocument(doc) {
    try {
      const result = await ext.runtime.sendMessage({type: "fetchDocument", url: doc.url});
      if (!result?.ok) {
        log(`Could not download ${doc.label}: ${result?.error || "unknown error"}`);
        return null;
      }

      const binary = atob(result.base64);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i += 1) {
        bytes[i] = binary.charCodeAt(i);
      }

      const name = decodeURIComponent(doc.url.split("/").pop().split("?")[0]) || "document.pdf";
      return new File([bytes], name, {type: result.contentType || "application/pdf"});
    } catch (error) {
      log(`Could not download ${doc.label}: ${error}`);
      return null;
    }
  }

  function attachFile(input, file) {
    try {
      const transfer = new DataTransfer();
      transfer.items.add(file);
      input.files = transfer.files;
      input.dataset.dncUsed = "1";
      input.dispatchEvent(new Event("input", {bubbles: true}));
      input.dispatchEvent(new Event("change", {bubbles: true}));
      return true;
    } catch (error) {
      log(`Could not attach ${file.name}: ${error}`);
      return false;
    }
  }

  async function pickOption(labels, hints, prefix) {
    if (!hints || hints.length === 0) return false;
    const key = fieldKey(labels, hints.join("|"), prefix);
    if (FILLED.has(key)) return true;

    const input = findControl(labels);
    if (!input) return false;
    if (matchHint(input.value, hints)) {
      FILLED.add(key);
      return true;
    }

    const options = await openOptions(input);
    const choice = bestOption(options, hints);
    if (!choice) {
      closeOptions(input);
      updatePanel(`Choose ${labels[0]} yourself — no option matched ${hints.join(", ")}.`);
      return false;
    }

    choice.click();
    await sleep(700);
    FILLED.add(key);
    log(`Selected ${labels[0]}: ${optionText(choice)}.`);
    return true;
  }

  async function openOptions(input) {
    input.focus();
    input.click();
    input.dispatchEvent(new KeyboardEvent("keydown", {key: "ArrowDown", code: "ArrowDown", bubbles: true}));

    for (let attempt = 0; attempt < 25; attempt += 1) {
      await sleep(200);
      const options = optionsFor(input);
      if (options.length > 0) return options;
    }
    return [];
  }

  // Stale listboxes linger in the DOM, so scope to the popup this input owns.
  function optionsFor(input) {
    const id = input.getAttribute("aria-controls");
    const popup = id ? document.getElementById(id) : null;
    const root = popup || document;
    return Array.from(root.querySelectorAll("[role='option']"));
  }

  function closeOptions(input) {
    input.dispatchEvent(new KeyboardEvent("keydown", {key: "Escape", code: "Escape", bubbles: true}));
  }

  // Option labels carry court-specific suffixes ("Other Complaint - $370.00"),
  // so try exact, then prefix, then substring, hint by hint.
  function bestOption(options, hints) {
    const tiers = [
      (option, hint) => norm(optionText(option)) === norm(hint),
      (option, hint) => norm(optionText(option)).startsWith(norm(hint)),
      (option, hint) => norm(optionText(option)).includes(norm(hint))
    ];

    for (const matches of tiers) {
      for (const hint of hints) {
        const found = options.find((option) => optionText(option) && matches(option, hint));
        if (found) return found;
      }
    }
    return null;
  }

  function matchHint(value, hints) {
    return Boolean(value) && hints.some((hint) => norm(value).startsWith(norm(hint)));
  }

  function optionText(option) {
    return (option.textContent || "").trim();
  }

  async function setField(labels, value, prefix) {
    if (value == null || value === "") return false;
    const key = fieldKey(labels, value, prefix);
    if (FILLED.has(key)) return true;
    const control = findControl(labels);
    if (!control) return false;
    setNativeValue(control, value);
    FILLED.add(key);
    log(`Filled ${labels[0]}.`);
    return true;
  }

  // Scope lookups to the open modal so background fields are never touched.
  function scopeRoot() {
    return openModal() || document;
  }

  // Only a visible dialog counts: scoping lookups into a hidden one would make
  // every field on the page invisible to the helper.
  function openModal() {
    return Array.from(
      document.querySelectorAll("ngb-modal-window, forge-dialog, dialog[open], [role='dialog']")
    ).find((el) => el.offsetParent !== null || el.getClientRects().length > 0);
  }

  function findControl(labels) {
    const root = scopeRoot();
    for (const label of labels) {
      const byFor = findByLabelFor(label, root);
      if (byFor) return byFor;
      try {
        const byAria = root.querySelector(`[aria-label="${cssEscape(label)}"]`);
        if (byAria) return byAria;
      } catch (_err) {}
      const near = findNearLabel(label, root);
      if (near) return near;
    }
    return null;
  }

  function findByLabelFor(labelText, root) {
    const labels = Array.from(root.querySelectorAll("label"));
    const match =
      labels.find((el) => norm(labelLine(el)) === norm(labelText)) ||
      labels.find((el) => norm(labelLine(el)).startsWith(norm(labelText)));
    if (!match) return null;
    if (match.htmlFor) {
      const target = document.getElementById(match.htmlFor);
      if (target) return target;
    }
    return match.querySelector("input, select, textarea, [role='combobox']") || nextControl(match);
  }

  // Forge labels carry helper text ("Court Location\n(Required)\nThis is…").
  function labelLine(el) {
    return (el.innerText || el.textContent || "").split("\n")[0];
  }

  function findNearLabel(labelText, root) {
    const nodes = Array.from(root.querySelectorAll("label, span, div, p, legend"));
    const match = nodes.find((el) => {
      const text = (el.childNodes[0]?.textContent || el.innerText || "").trim();
      return (
        (text && norm(text) === norm(labelText)) ||
        (text && norm(text).startsWith(norm(labelText)) && text.length < 40)
      );
    });
    if (!match) return null;
    return match.querySelector("input, select, textarea, [role='combobox']") || nextControl(match);
  }

  function nextControl(el) {
    let node = el.nextElementSibling;
    for (let i = 0; i < 4 && node; i += 1) {
      if (node.matches?.("input, select, textarea, [role='combobox']")) return node;
      const inner = node.querySelector?.("input, select, textarea, [role='combobox']");
      if (inner) return inner;
      node = node.nextElementSibling;
    }
    const parent = el.closest(".form-group, .ty-field, .mat-form-field, .ofs-field, [class*='field']");
    return parent?.querySelector("input, select, textarea, [role='combobox']") || null;
  }

  function clickables(re, scope) {
    return Array.from((scope || document).querySelectorAll(CLICKABLE)).filter((el) => {
      const text = (el.innerText || el.value || el.getAttribute("aria-label") || "").trim();
      if (!re.test(text)) return false;
      return !FORBIDDEN_CLICK.test(text) || SAVE.test(text) || START_NEW_CASE.test(text);
    });
  }

  // Wizard navigation stays disabled until the step validates, so wait for it
  // rather than clicking once and marking the button as done.
  async function clickWhenEnabled(re, key, scope, timeoutMs = 12000) {
    if (FILLED.has(`click:${key}`)) return false;
    const deadline = Date.now() + timeoutMs;

    while (Date.now() < deadline) {
      const button = clickables(re, scope)[0];
      if (button && !isDisabled(button)) {
        button.click();
        FILLED.add(`click:${key}`);
        log(`Clicked ${(button.innerText || key).trim()}.`);
        await sleep(600);
        return true;
      }
      if (!button) return false;
      await sleep(400);
    }
    return false;
  }

  // The wizard gives its own controls stable ids, which beat matching on copy.
  async function clickById(id, key) {
    const guard = `click:${key || id}`;
    if (FILLED.has(guard)) return false;
    const button = document.getElementById(id);
    if (!button || isDisabled(button)) return false;
    button.click();
    FILLED.add(guard);
    await sleep(600);
    return true;
  }

  function isDisabled(el) {
    return Boolean(
      el.disabled ||
        el.hasAttribute("disabled") ||
        el.getAttribute("aria-disabled") === "true" ||
        el.classList.contains("disabled")
    );
  }

  async function waitFor(check, timeoutMs = 8000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      await sleep(250);
      if (check()) return true;
    }
    return false;
  }

  async function waitForStepChange(from, timeoutMs = 15000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      await sleep(300);
      if (currentStep() !== from) return true;
    }
    return false;
  }

  async function waitForModalClose(timeoutMs = 10000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      await sleep(300);
      if (!openModal()) return true;
    }
    return false;
  }

  function onSignIn() {
    const text = pageText();
    return /sign in to your account/i.test(text) && !/start filing|start a new case/i.test(text);
  }

  function setNativeValue(el, value) {
    const proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, "value")?.set;
    if (setter) setter.call(el, value);
    else el.value = value;
    el.dispatchEvent(new Event("input", {bubbles: true}));
    el.dispatchEvent(new Event("change", {bubbles: true}));
    el.dispatchEvent(new KeyboardEvent("keyup", {bubbles: true}));
    el.dispatchEvent(new Event("blur", {bubbles: true}));
  }

  function fieldKey(labels, value, prefix) {
    return `${prefix || "case"}::${labels[0]}::${value}`;
  }

  // Court labels mix hyphens and en dashes ("Santa Clara – Civil").
  function norm(text) {
    return (text || "")
      .toLowerCase()
      .replace(/[\u2010-\u2015]/g, "-")
      .replace(/\s+/g, " ")
      .trim();
  }

  function cssEscape(text) {
    return text.replace(/"/g, '\\"');
  }

  function pageText() {
    return (document.body?.innerText || "").slice(0, 20000);
  }

  function ensurePanel() {
    if (document.getElementById(PANEL_ID)) {
      updatePanel();
      return;
    }
    const panel = document.createElement("aside");
    panel.id = PANEL_ID;
    panel.setAttribute("role", "complementary");
    Object.assign(panel.style, {
      position: "fixed",
      top: "12px",
      right: "12px",
      zIndex: "2147483646",
      width: "320px",
      maxHeight: "90vh",
      overflow: "auto",
      background: "#0f172a",
      color: "#e2e8f0",
      font: "13px/1.45 ui-sans-serif, system-ui, sans-serif",
      borderRadius: "12px",
      boxShadow: "0 12px 40px rgba(0,0,0,.35)",
      padding: "14px 16px 16px"
    });
    document.documentElement.appendChild(panel);
    updatePanel();
  }

  function updatePanel(status) {
    const data = restorePayload();
    const panel = document.getElementById(PANEL_ID);
    if (!panel || !data) return;

    const docs = (data.documents || [])
      .map((doc) => {
        const attached = FILLED.has(`doc:${doc.url}`) ? " ✓" : "";
        const lead = isLead(doc) ? " (lead)" : "";
        return `<li><a href="${escapeHtml(doc.url)}" target="_blank" rel="noreferrer" style="color:#7dd3fc">${escapeHtml(doc.label)}</a>${lead}${attached}</li>`;
      })
      .join("");

    const statusText = status || `Step: ${currentStep()}. The helper never clicks Submit.`;

    const html = `
      <div style="font-weight:700;font-size:14px;margin-bottom:6px">DNC Watchdog eFile helper</div>
      <div style="color:#94a3b8;margin-bottom:10px">Odyssey eFileCA · case ${data.case_id}<br>${escapeHtml(data.venue_label || "")} · $${escapeHtml(data.claim_amount || "")}</div>
      <div style="background:#1e293b;border-radius:8px;padding:8px 10px;margin-bottom:10px">${escapeHtml(statusText)}</div>
      <div><strong>Plaintiff</strong><br>${escapeHtml(data.plaintiff?.name || "")}<br>${escapeHtml(formatAddress(data.plaintiff?.address))}</div>
      <div style="margin-top:8px"><strong>Defendant</strong><br>${escapeHtml(data.defendant?.name || "")}<br>${escapeHtml(formatAddress(data.defendant?.address))}${data.defendant?.phone ? `<br>${escapeHtml(data.defendant.phone)}` : ""}</div>
      ${data.defendant?.contact ? `<div style="margin-top:8px"><strong>Agent for service</strong><br>${escapeHtml(data.defendant.contact.name || "")}${data.defendant.contact.title ? ` · ${escapeHtml(data.defendant.contact.title)}` : ""}<br>${escapeHtml(formatAddress(data.defendant.contact.address))}<br><em>Add on the Service step yourself.</em></div>` : ""}
      <div style="margin-top:8px"><strong>Court forms</strong> — attached automatically on the Filings step:<ul style="margin:4px 0 0 16px;padding:0">${docs || "<li>Generate a filing draft first</li>"}</ul></div>
      <p style="margin:10px 0 0;color:#fbbf24">The helper never submits or pays. You click Submit after review.</p>
    `;

    if (panel.innerHTML !== html) panel.innerHTML = html;
  }

  function formatAddress(address) {
    if (!address) return "";
    return [address.street, [address.city, address.state, address.zip].filter(Boolean).join(", ")]
      .filter(Boolean)
      .join(", ");
  }

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function log(message) {
    const data = restorePayload();
    if (data) updatePanel(message);
  }

  function startObserver() {
    if (observer) return;
    let queued = null;

    const schedule = () => {
      if (queued) return;
      queued = setTimeout(() => {
        queued = null;
        if (restorePayload()) runFill();
      }, 500);
    };

    observer = new MutationObserver((mutations) => {
      // Ignore our own panel writes. Reacting to them would schedule another
      // pass, which rewrites the panel again, and the loop pegs a CPU core.
      const panel = document.getElementById(PANEL_ID);
      if (panel && mutations.every((record) => panel.contains(record.target))) return;
      schedule();
    });
    observer.observe(document.documentElement, {childList: true, subtree: true});

    setInterval(() => {
      if (restorePayload()) runFill();
    }, 2000);
  }

  restorePayload();
  startObserver();
  if (payload) {
    ensurePanel();
    runFill();
  }
})();

function show(enabled, useSettingsInsteadOfPreferences) {
    if (useSettingsInsteadOfPreferences) {
        document.getElementsByClassName('state-on')[0].innerText =
            "The helper is on. In Safari Settings → Extensions, allow tools.usps.com, usps.com, 127.0.0.1, and localhost. Then reload DNC Watchdog.";
        document.getElementsByClassName('state-off')[0].innerText =
            "The helper is off. Turn it on in Safari Settings → Extensions, then allow USPS.com and localhost.";
        document.getElementsByClassName('state-unknown')[0].innerText =
            "Turn on DNC Watchdog USPS Helper in Safari Settings, then allow it on USPS.com and localhost.";
        document.getElementsByClassName('open-preferences')[0].innerText = "Quit and Open Safari Settings…";
    }

    if (typeof enabled === "boolean") {
        document.body.classList.toggle(`state-on`, enabled);
        document.body.classList.toggle(`state-off`, !enabled);
    } else {
        document.body.classList.remove(`state-on`);
        document.body.classList.remove(`state-off`);
    }
}

function openPreferences() {
    webkit.messageHandlers.controller.postMessage("open-preferences");
}

document.querySelector("button.open-preferences").addEventListener("click", openPreferences);

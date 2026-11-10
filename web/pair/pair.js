// The pairing page: reads the link's fragment, then offers the right next
// step for the phone. Parsing lives in pairing.js (tested against fixtures).
import { PairingError, androidIntentUrl, cameBackWithoutApp, extractParams, parsePairingParams } from "./pairing.js";

const APK_URL = "https://github.com/GiamSoo23/Mox/releases/latest/download/Mox.apk";

const $ = (id) => document.getElementById(id);
const show = (id) => { $(id).hidden = false; };

/** "android", "ios" or "desktop", from the user agent. */
function platform() {
  const ua = navigator.userAgent;
  if (/Android/i.test(ua)) return "android";
  if (/iPhone|iPad|iPod/i.test(ua) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)) {
    return "ios";
  }
  return "desktop";
}

/** Open in Mox fails until Mox is installed, so it waits for the person to confirm. */
function setOpenEnabled(enabled, intent) {
  const button = $("open-app");
  if (enabled) button.href = intent;
  else button.removeAttribute("href");
  button.classList.toggle("disabled", !enabled);
  button.setAttribute("aria-disabled", String(!enabled));
}

const SECTIONS = ["loading", "error", "pairing", "android", "ios", "desktop"];

/** True when this page was opened from an icon on the iPhone home screen. */
function openedFromHomeScreen() {
  return window.matchMedia("(display-mode: standalone)").matches || navigator.standalone === true;
}

function render() {
  // Added to the home screen from here instead of from Mox for iPhone:
  // go straight to the app, which pairs from the same fragment.
  if (platform() === "ios" && openedFromHomeScreen()) {
    window.location.replace(`../app/${window.location.hash}`);
    return;
  }
  // Start from scratch every time: a new link can arrive in the same tab
  // with only the fragment changed, which doesn't reload the page.
  for (const id of SECTIONS) $(id).hidden = true;
  let raw;
  let config;
  try {
    raw = extractParams(window.location.href);
    config = parsePairingParams(raw);
  } catch (error) {
    $("error-message").textContent = error instanceof PairingError
      ? error.message
      : "Something went wrong reading this link.";
    show("error");
    return;
  }

  // Never display the password or the key.
  $("desktop-name").textContent = config.desktopName ?? "your computer";
  $("project-host").textContent = new URL(config.projectUrl).host;
  show("pairing");

  const where = platform();
  if (where === "android") {
    $("download-apk").href = APK_URL;
    const intent = androidIntentUrl(raw, window.location.href);
    $("installed").checked = false;
    $("installed").onchange = () => setOpenEnabled($("installed").checked, intent);
    setOpenEnabled(false, intent);
    $("app-missing").hidden = !cameBackWithoutApp(window.location.href);
    show("android");
  } else if (where === "ios") {
    // Same fragment: the parameters still never reach a server.
    $("open-iphone").href = `../app/#${raw}`;
    show("ios");
  } else {
    show(where);
  }
}

render();
window.addEventListener("hashchange", render);

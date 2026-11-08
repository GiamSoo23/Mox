// The pairing page: reads the link's fragment, then offers the right next
// step for the phone. Parsing lives in pairing.js (tested against fixtures).
import { PairingError, extractParams, parsePairingParams } from "./pairing.js";

const APK_URL = "https://github.com/GiamSoo23/Mox/releases/latest/download/Mox.apk";
const ANDROID_PACKAGE = "com.mox.app";

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

/**
 * The Android hand-off: opens Mox if it's installed, otherwise the browser
 * follows the fallback and downloads the APK (PROTOCOL.md §8.1).
 */
function androidIntentUrl(rawParams) {
  return `intent://pair?${rawParams}#Intent;scheme=mox;package=${ANDROID_PACKAGE};` +
    `S.browser_fallback_url=${encodeURIComponent(APK_URL)};end`;
}

const SECTIONS = ["loading", "error", "pairing", "android", "ios", "desktop"];

function render() {
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
    $("open-app").href = androidIntentUrl(raw);
    show("android");
  } else {
    show(where);
  }
}

render();
window.addEventListener("hashchange", render);

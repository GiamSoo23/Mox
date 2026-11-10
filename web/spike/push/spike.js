// The push test page (#54). Everything shown here stays on this phone,
// except the subscription you choose to share with your Mac.
const VAPID_PUBLIC_KEY = "BDrSIPI9gsjkmVBl8I0G3TeVN-Ahrmqwl0DDtSBkdLQzyAgtHgwdu77Yu6Bl-rHIM0l8wnFi83Q2n-YgI-pWrUc";

const $ = (id) => document.getElementById(id);
const log = (text) => {
  const item = document.createElement("li");
  item.textContent = `${new Date().toLocaleTimeString()} · ${text}`;
  $("status").append(item);
};

function keyBytes(base64url) {
  const base64 = base64url.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

const standalone = window.matchMedia("(display-mode: standalone)").matches || navigator.standalone === true;
let subscriptionText = "";

async function showSubscription(subscription) {
  subscriptionText = JSON.stringify(subscription);
  $("subscribed").hidden = false;
  log("Subscribed. Share it with your Mac.");
}

async function enable(event) {
  event.preventDefault();
  try {
    const permission = await Notification.requestPermission();
    log(`Notification permission: ${permission}`);
    if (permission !== "granted") return;
    const registration = await navigator.serviceWorker.ready;
    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: keyBytes(VAPID_PUBLIC_KEY),
    });
    $("enable").hidden = true;
    await showSubscription(subscription);
  } catch (error) {
    log(`Couldn't subscribe: ${error.message}`);
  }
}

async function share(event) {
  event.preventDefault();
  try {
    await navigator.share({ title: "Mox push subscription", text: subscriptionText });
    $("share-result").textContent = "Shared.";
  } catch (error) {
    $("share-result").textContent = `Share failed: ${error.message}`;
  }
}

async function copy(text, result) {
  try {
    await navigator.clipboard.writeText(text);
    result.textContent = "Copied.";
    return true;
  } catch (error) {
    result.textContent = `Copy failed: ${error.message}`;
    return false;
  }
}

/** Shows the last tapped notification, saved by the service worker. */
async function showTap() {
  const cache = await caches.open("mox-spike");
  const saved = await cache.match(new URL("last-tap", location.href).href);
  if (!saved) return;
  await cache.delete(new URL("last-tap", location.href).href);
  const tap = await saved.json();
  const delay = tap.sentAt ? Math.round((tap.tappedAt - Number(tap.sentAt)) / 1000) : null;
  $("opened").hidden = false;
  $("opened-detail").textContent = `Tapped ${delay === null ? "" : `${delay} s after it was sent`}. Text: "${tap.text}"`;
  // Can the page copy right after the tap, with no second tap? (iOS may refuse.)
  const auto = await copy(tap.text, $("copy-result"));
  log(`Copy right after opening: ${auto ? "worked" : "refused"}`);
  $("copy-received").onclick = (event) => { event.preventDefault(); copy(tap.text, $("copy-result")); };
}

async function start() {
  log(`Opened ${standalone ? "from the home screen" : "in the browser"}`);
  if (!("serviceWorker" in navigator) || !("PushManager" in window)) {
    log("This browser can't receive Web Push here.");
    if (!standalone) $("install").hidden = false;
    return;
  }
  navigator.serviceWorker.addEventListener("message", (event) => {
    if (event.data && event.data.type === "tapped") showTap();
    if (event.data && event.data.type === "version") log(`Service worker: ${event.data.version}`);
  });
  document.addEventListener("visibilitychange", () => { if (!document.hidden) showTap(); });
  await navigator.serviceWorker.register("sw.js", { updateViaCache: "none" });
  const registration = await navigator.serviceWorker.ready;
  registration.update().catch(() => {});
  if (registration.active) registration.active.postMessage("version");
  await showTap();
  const existing = await registration.pushManager.getSubscription();
  if (existing) {
    await showSubscription(existing);
  } else {
    $("enable").hidden = false;
  }
  $("enable-button").onclick = enable;
  $("share-button").onclick = share;
  $("copy-button").onclick = (event) => { event.preventDefault(); copy(subscriptionText, $("share-result")); };
}

start();

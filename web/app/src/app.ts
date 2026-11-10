// Mox for iPhone (#54): a home screen web app that pairs with the desktop,
// receives through Web Push, and sends photos, files and text.
import { parsePairingLink } from "../../pair/pairing.js";
import { MoxClient } from "./client.ts";
import { base64UrlToBytes, checkFileSize, humanSize, isNew, type Item, type Settings, sourceName } from "./protocol.ts";
import { store } from "./store.ts";

const $ = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;
const show = (id: string, visible = true) => ($(id).hidden = !visible);
const standalone = matchMedia("(display-mode: standalone)").matches ||
  (navigator as Navigator & { standalone?: boolean }).standalone === true;
const TAP_URL = new URL("last-tap", location.href).href;

let client: MoxClient | null = null;
let latest: { item: Item; blob?: Blob; text?: string } | null = null;

function message(text: string, isError = false) {
  const box = $("message");
  box.textContent = text;
  box.classList.toggle("error", isError);
  box.hidden = text === "";
}

async function run(task: () => Promise<void>) {
  try {
    await task();
  } catch (error) {
    message(error instanceof Error ? error.message : String(error), true);
  }
}

// ---- Screens ---------------------------------------------------------------

function render() {
  for (const id of ["install", "pair", "home"]) show(id, false);
  const settings = store.settings();
  if (!standalone) {
    show("install");
    show("copy-code-step", location.hash.length > 1);
    return;
  }
  if (!settings) {
    show("pair");
    return;
  }
  client = new MoxClient(settings, store.deviceId());
  $("paired-with").textContent = settings.desktopName ?? "your computer";
  show("home");
  void run(prepareNotifications);
  void run(() => refresh(false));
}

// ---- Pairing (PROTOCOL.md §8.3) -----------------------------------------------

async function pair(link: string) {
  const parsed = parsePairingLink(link.trim()) as Settings;
  const candidate = new MoxClient(parsed, store.deviceId());
  message("Pairing…");
  await candidate.checkSchema();
  store.saveSettings(parsed);
  message(`Paired with ${parsed.desktopName ?? "your computer"}.`);
  render();
}

// ---- Notifications ---------------------------------------------------------

async function prepareNotifications() {
  const supported = "serviceWorker" in navigator && "PushManager" in window;
  show("notify-card", supported);
  if (!supported) return;
  const registration = await navigator.serviceWorker.register("sw.js", { updateViaCache: "none" });
  await navigator.serviceWorker.ready;
  const on = Notification.permission === "granted" && (await registration.pushManager.getSubscription()) !== null;
  show("notify-off", !on);
  show("notify-on", on);
  if (on) await subscribe(registration); // Keeps the project's copy current.
}

async function subscribe(registration: ServiceWorkerRegistration) {
  if (!client) return;
  const key = await client.vapidPublicKey();
  if (!key) {
    throw new Error("Your project doesn't have iPhone notifications yet. On your Mac, choose Set Up Again.");
  }
  let subscription = await registration.pushManager.getSubscription();
  // Setting Mox up again makes new keys, and an old subscription stops working.
  if (subscription && store.vapidKey() !== key) {
    await subscription.unsubscribe();
    subscription = null;
  }
  subscription ??= await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: base64UrlToBytes(key) as BufferSource,
  });
  store.setVapidKey(key);
  await client.savePushSubscription(subscription);
}

async function enableNotifications() {
  const permission = await Notification.requestPermission();
  if (permission !== "granted") {
    throw new Error("Notifications are off. Turn them on in Settings → Notifications → Mox.");
  }
  await subscribe(await navigator.serviceWorker.ready);
  show("notify-off", false);
  show("notify-on");
  message("Notifications are on.");
}

// ---- Receiving (PROTOCOL.md §6) ----------------------------------------------

/** Reads the slot. `fromTap` is true right after tapping a notification. */
async function refresh(fromTap: boolean) {
  if (!client) return;
  const item = await client.current();
  if (!item) {
    latest = null;
    $("latest-title").textContent = "Nothing sent yet";
    $("latest-detail").textContent = "Send something from your computer.";
    for (const id of ["copy-text", "save-file", "preview"]) show(id, false);
    return;
  }
  const fresh = isNew(item, store.deviceId(), store.lastHandled());
  latest = { item };
  $("latest-title").textContent = item.kind === "text"
    ? `Text from ${sourceName(item.source_platform)}`
    : `${item.original_name}`;
  $("latest-detail").textContent = item.kind === "text"
    ? (fresh ? "New" : "")
    : `${humanSize(item.size_bytes)} · from ${sourceName(item.source_platform)}${fresh ? " · new" : ""}`;
  show("copy-text", item.kind === "text");
  show("save-file", item.kind !== "text");
  show("preview", false);
  if (fresh) store.setLastHandled(item.uploaded_at);
  if (item.kind === "text") {
    const text = await (await client.download()).text();
    latest.text = text;
    $("latest-detail").textContent = text;
    // Right after a tap, iOS lets the page copy without another tap.
    if (fromTap || fresh) await copyText(true);
  }
}

async function copyText(automatic = false) {
  if (!latest?.text) return;
  try {
    await navigator.clipboard.writeText(latest.text);
    message("Copied. Paste it anywhere.");
  } catch {
    if (!automatic) throw new Error("iPhone didn't allow copying. Tap Copy again.");
    message("Tap Copy to put it on the clipboard.");
  }
}

async function saveFile() {
  if (!client || !latest) return;
  message("Downloading…");
  latest.blob ??= await client.download();
  const { item, blob } = latest;
  const file = new File([blob], item.original_name, { type: item.mime_type ?? blob.type });
  if (file.type.startsWith("image/")) {
    const preview = $<HTMLImageElement>("preview");
    preview.src = URL.createObjectURL(file);
    show("preview");
  }
  message("");
  if (navigator.canShare?.({ files: [file] })) {
    // The share sheet has Save Image, Save to Files, and every app.
    await navigator.share({ files: [file] }).catch((error: Error) => {
      if (error.name !== "AbortError") throw error;
    });
  } else {
    const link = document.createElement("a");
    link.href = URL.createObjectURL(file);
    link.download = file.name;
    link.click();
  }
}

/** The service worker saves the tapped notification for the page. */
async function checkTap() {
  const cache = await caches.open("mox");
  if (!(await cache.match(TAP_URL))) return;
  await cache.delete(TAP_URL);
  await refresh(true);
}

// ---- Sending ----------------------------------------------------------------

async function sendFile(file: File) {
  if (!client) return;
  checkFileSize(file.size);
  message(`Sending ${file.name}…`);
  await client.sendFile(file);
  message(`Sent ${file.name}.`);
  await refresh(false);
}

async function sendText() {
  if (!client) return;
  const box = $<HTMLTextAreaElement>("text-to-send");
  message("Sending text…");
  await client.sendText(box.value);
  box.value = "";
  message("Sent.");
  await refresh(false);
}

// ---- Wiring -----------------------------------------------------------------

function onClick(id: string, task: () => Promise<void>) {
  $(id).addEventListener("click", (event) => {
    event.preventDefault();
    void run(task);
  });
}

onClick("copy-code", async () => {
  await navigator.clipboard.writeText(location.href);
  history.replaceState(null, "", location.pathname); // Don't keep the code in the address.
  message("Copied. Now add Mox to your home screen.");
});
onClick("paste-code", async () => pair(await navigator.clipboard.readText()));
onClick("pair-typed", () => pair($<HTMLTextAreaElement>("typed-code").value));
onClick("enable-notifications", enableNotifications);
onClick("refresh", () => refresh(false));
onClick("copy-text", () => copyText());
onClick("save-file", saveFile);
onClick("send-text", sendText);
onClick("unpair", async () => {
  if (!confirm("Unpair this iPhone? You can pair it again from your computer.")) return;
  store.saveSettings(null);
  message("");
  render();
});
$<HTMLInputElement>("file-to-send").addEventListener("change", (event) => {
  const input = event.target as HTMLInputElement;
  const file = input.files?.[0];
  input.value = "";
  if (file) void run(() => sendFile(file));
});
navigator.serviceWorker?.addEventListener("message", (event) => {
  if (event.data?.type === "tapped") void run(checkTap);
});
document.addEventListener("visibilitychange", () => {
  if (!document.hidden && client) void run(async () => {
    await checkTap();
    await refresh(false);
  });
});

render();
if (standalone && store.settings()) void run(checkTap);

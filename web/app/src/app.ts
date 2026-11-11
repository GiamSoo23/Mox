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

/** Short news for the person: next to the latest item once paired, at the top before. */
function message(text: string, isError = false) {
  const box = $("home").hidden ? $("message") : $("status");
  box.textContent = text;
  box.classList.toggle("error", isError);
  box.hidden = text === "";
}

async function run(task: () => Promise<unknown>) {
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
  // Opened with a pairing code in the address: pair with it, even if this
  // iPhone was paired before. A new code replaces the old pairing, which
  // stops working whenever Mox is set up again.
  if (location.hash.length > 1) {
    show("pair");
    void run(() => pair(location.href));
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
  // Never keep the code (it holds the Mox password) in the address.
  history.replaceState(null, "", location.pathname);
  message(`Paired with ${parsed.desktopName ?? "your computer"}.`);
  render();
}

// ---- Notifications ---------------------------------------------------------

let notificationsOn = false;

async function prepareNotifications() {
  const supported = "serviceWorker" in navigator && "PushManager" in window;
  if (supported) {
    const registration = await navigator.serviceWorker.register("sw.js", { updateViaCache: "none" });
    await navigator.serviceWorker.ready;
    notificationsOn = Notification.permission === "granted" &&
      (await registration.pushManager.getSubscription()) !== null;
    if (notificationsOn) await subscribe(registration); // Keeps the project's copy current.
  }
  updateSetupCard(!supported);
}

/**
 * The setup steps show until both are done, then get out of the way.
 * "Setup steps" at the bottom brings them back.
 */
function updateSetupCard(notificationsUnsupported = false, forceOpen = false) {
  const notifyDone = notificationsOn || notificationsUnsupported;
  show("enable-notifications", !notifyDone);
  ($("step-notify").querySelector(".done") as HTMLElement).hidden = !notificationsOn;
  show("step-notify", !notificationsUnsupported);
  show("shortcut-done", !store.shortcutAdded());
  show("setup-card", forceOpen || !notifyDone || !store.shortcutAdded());
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
  notificationsOn = true;
  updateSetupCard();
  message("Notifications are on.");
}

// ---- Receiving (PROTOCOL.md §6) ----------------------------------------------

/** Reads the slot. `fromTap` is true right after tapping a notification. */
async function refresh(fromTap: boolean): Promise<boolean> {
  if (!client) return false;
  const item = await client.current();
  if (!item) {
    latest = null;
    $("latest-title").textContent = "Nothing sent yet";
    $("latest-detail").textContent = "Send something from your computer.";
    for (const id of ["copy-text", "save-file"]) show(id, false);
    return false;
  }
  const fresh = isNew(item, store.deviceId(), store.lastHandled());
  latest = { item };
  $("latest-title").textContent = item.kind === "text"
    ? `Text from ${sourceName(item.source_platform)}`
    : `${item.original_name}`;
  $("latest-detail").textContent = item.kind === "text"
    ? (fresh ? "New" : "")
    : `${humanSize(item.size_bytes)} · from ${sourceName(item.source_platform)}${fresh ? " · new" : ""}`;
  show("copy-text", item.kind === "text" || isImage(item));
  show("save-file", item.kind !== "text");
  if (fresh) store.setLastHandled(item.uploaded_at);
  if (item.kind === "text") $("latest-detail").textContent = await textOf();
  // After a tap, checkTap has already started the copy.
  if (fresh && !fromTap) await copyLatest(true);
  return fresh;
}

const isImage = (item: Item) => item.kind === "file" && (item.mime_type ?? "").startsWith("image/");

/** The latest item's bytes, downloaded once. */
async function blobOf(): Promise<Blob> {
  if (!client || !latest) throw new Error("Nothing to copy yet.");
  latest.blob ??= await client.download();
  return latest.blob;
}

async function textOf(): Promise<string> {
  if (latest && latest.text === undefined) latest.text = await (await blobOf()).text();
  return latest?.text ?? "";
}


/** iPhone's clipboard takes images as PNG, so photos (JPEG, HEIC) are converted. */
async function pngOf(blob: Blob): Promise<Blob> {
  if (blob.type === "image/png") return blob;
  const url = URL.createObjectURL(blob);
  try {
    const image = new Image();
    image.src = url;
    await image.decode();
    const canvas = document.createElement("canvas");
    canvas.width = image.naturalWidth;
    canvas.height = image.naturalHeight;
    canvas.getContext("2d")!.drawImage(image, 0, 0);
    return await new Promise<Blob>((resolve, reject) =>
      canvas.toBlob((png) => (png ? resolve(png) : reject(new Error("Couldn't prepare the image."))), "image/png")
    );
  } finally {
    URL.revokeObjectURL(url);
  }
}

/**
 * Puts the latest text or image on the clipboard. The ClipboardItem is
 * created right away with promises, so iPhone still counts the tap that
 * started it while the content downloads.
 */
async function copyLatest(automatic = false) {
  if (!latest) return;
  const { item } = latest;
  let content: Record<string, Promise<Blob>>;
  if (item.kind === "text") {
    content = { "text/plain": textOf().then((text) => new Blob([text], { type: "text/plain" })) };
  } else if (isImage(item)) {
    content = { "image/png": blobOf().then(pngOf) };
  } else {
    if (!automatic) message("This kind of file can't go on the clipboard. Use Save or share.");
    return;
  }
  try {
    await navigator.clipboard.write([new ClipboardItem(content)]);
    message(item.kind === "text" ? "Copied. Paste it anywhere." : "Image copied. Paste it in any chat.");
  } catch {
    if (!automatic) throw new Error("iPhone didn't allow copying. Tap Copy again.");
    message("Tap Copy to put it on the clipboard.");
  }
}

async function saveFile() {
  if (!client || !latest) return;
  message("Downloading…");
  const blob = await blobOf();
  const { item } = latest;
  const file = new File([blob], item.original_name, { type: item.mime_type ?? blob.type });
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

/**
 * The service worker saves the tapped notification for the page. iPhone
 * allows copying only for a moment after the tap, so the copy starts at
 * once, with the content still downloading, instead of after the download.
 */
async function checkTap() {
  const cache = await caches.open("mox");
  const saved = await cache.match(TAP_URL);
  if (!saved) return;
  await cache.delete(TAP_URL);
  const tap = await saved.json().catch(() => ({})) as { kind?: string };
  const loaded = refresh(true);
  const type = tap.kind === "text" ? "text/plain" : tap.kind === "file" ? "image/png" : null;
  if (type) {
    const content = loaded.then(async () => {
      if (!latest) throw new Error("Nothing to copy.");
      if (type === "text/plain") return new Blob([await textOf()], { type });
      if (!isImage(latest.item)) throw new Error("Not an image.");
      return pngOf(await blobOf());
    });
    navigator.clipboard.write([new ClipboardItem({ [type]: content })])
      .then(() => message(type === "text/plain" ? "Copied. Paste it anywhere." : "Image copied. Paste it in any chat."))
      .catch(() => message(type === "text/plain" ? "Tap Copy to put it on the clipboard." : ""));
  }
  await loaded;
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

function onClick(id: string, task: () => Promise<unknown>) {
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
onClick("shortcut-done", async () => {
  store.setShortcutAdded(true);
  updateSetupCard();
});
onClick("show-setup", async () => updateSetupCard(false, true));
// The Send to Mox shortcut's setup code (#27): where mox-send lives and who to sign in as.
onClick("copy-setup", async () => {
  const settings = store.settings();
  if (!settings) return;
  await navigator.clipboard.writeText(JSON.stringify({
    url: `${settings.projectUrl.replace(/\/$/, "")}/functions/v1/mox-send`,
    key: settings.publishableKey,
    email: settings.email,
    password: settings.password,
    device: store.deviceId(),
  }));
  message("Setup code copied. Now get the shortcut.");
});
onClick("refresh", async () => {
  message("Checking…");
  const fresh = await refresh(false);
  if (!fresh) message(`Up to date · checked at ${new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}`);
});
onClick("copy-text", () => copyLatest());
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

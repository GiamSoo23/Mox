// Service worker for the push test (#54), version 2. Shows each push as a
// notification. When it's tapped, it saves the payload where the page can
// read it, because iPhone opens the app without passing anything along.
const VERSION = "test v2";
const TAP = new URL("last-tap", self.registration.scope).href;

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));

self.addEventListener("message", (event) => {
  if (event.data === "version") event.source.postMessage({ type: "version", version: VERSION });
});

self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {
    data = { body: event.data ? event.data.text() : "" };
  }
  event.waitUntil(self.registration.showNotification(data.title || "Mox", {
    body: data.body || "",
    data: { text: data.text || "", sentAt: data.sentAt || "" },
  }));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const tap = { ...event.notification.data, tappedAt: Date.now() };
  event.waitUntil((async () => {
    const cache = await caches.open("mox-spike");
    await cache.put(TAP, new Response(JSON.stringify(tap)));
    const windows = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const client of windows) {
      client.postMessage({ type: "tapped" });
      if ("focus" in client) return client.focus();
    }
    return self.clients.openWindow(new URL("./", self.registration.scope).href);
  })());
});

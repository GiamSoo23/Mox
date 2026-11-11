// Mox for iPhone's service worker (#54). Shows each push as a notification.
// iPhone opens the app without passing anything along, so a tap is saved
// where the page looks for it.
const TAP_URL = new URL("last-tap", self.registration.scope).href;

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));

self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {
    data = {};
  }
  event.waitUntil(self.registration.showNotification(data.title || "Mox", {
    body: data.body || "",
    tag: "mox",
    data: { uploadedAt: data.uploadedAt || "", kind: data.kind || "" },
  }));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil((async () => {
    const cache = await caches.open("mox");
    await cache.put(TAP_URL, new Response(JSON.stringify(event.notification.data)));
    const windows = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const client of windows) {
      client.postMessage({ type: "tapped" });
      if ("focus" in client) return client.focus();
    }
    return self.clients.openWindow(self.registration.scope);
  })());
});

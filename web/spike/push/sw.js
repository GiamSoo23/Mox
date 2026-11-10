// Service worker for the push test (#54): shows each push as a
// notification, and opens the page with the payload when it's tapped.
self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {
    data = { body: event.data ? event.data.text() : "" };
  }
  const title = data.title || "Mox";
  const url = new URL("./", self.registration.scope);
  url.searchParams.set("from", "push");
  url.searchParams.set("sent", data.sentAt || "");
  url.searchParams.set("text", data.text || "");
  event.waitUntil(self.registration.showNotification(title, {
    body: data.body || "",
    data: { url: url.href },
  }));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const target = event.notification.data && event.notification.data.url;
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const client of windows) {
      if ("navigate" in client) {
        await client.navigate(target);
        return client.focus();
      }
    }
    return self.clients.openWindow(target);
  })());
});

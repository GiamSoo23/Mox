// What Mox for iPhone remembers on this device. Each home screen web app
// has its own storage, separate from Safari's.
import type { Settings } from "./protocol.ts";

const read = (key: string): string | null => {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
};
const write = (key: string, value: string | null) => {
  try {
    if (value === null) localStorage.removeItem(key);
    else localStorage.setItem(key, value);
  } catch {
    // Private browsing or storage turned off: Mox keeps working until it closes.
  }
};

export const store = {
  settings(): Settings | null {
    const raw = read("mox.settings");
    return raw ? JSON.parse(raw) as Settings : null;
  },
  saveSettings(settings: Settings | null) {
    write("mox.settings", settings && JSON.stringify(settings));
    write("mox.lastHandled", null);
    // A new pairing means a new setup code for the shortcut.
    write("mox.setupDone", null);
  },
  /** This installation's id (PROTOCOL.md §1). */
  deviceId(): string {
    let id = read("mox.deviceId");
    if (!id) {
      id = crypto.randomUUID();
      write("mox.deviceId", id);
    }
    return id;
  },
  /** The VAPID key the current push subscription was made with. */
  vapidKey: () => read("mox.vapidKey"),
  setVapidKey: (value: string) => write("mox.vapidKey", value),
  /** Whether the person said the Send to Mox shortcut is installed. */
  shortcutAdded: () => read("mox.shortcutAdded") === "yes",
  setShortcutAdded: (added: boolean) => write("mox.shortcutAdded", added ? "yes" : null),
  /** Whether the shortcut answered "Mox is ready", which finishes setup. */
  setupDone: () => read("mox.setupDone") === "yes",
  setSetupDone: (done: boolean) => write("mox.setupDone", done ? "yes" : null),
  lastHandled: () => read("mox.lastHandled"),
  setLastHandled: (value: string) => write("mox.lastHandled", value),
};

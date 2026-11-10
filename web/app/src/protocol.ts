// The Mox protocol as Mox for iPhone needs it (shared/PROTOCOL.md). Pure
// functions: no network, no DOM, so they run in Node's tests too.

export const MAX_FILE_BYTES = 52_428_800;
export const MAX_TEXT_BYTES = 1_000_000;
export const TEXT_FILE_NAME = "Text.txt";
const PLATFORMS = new Set(["macos", "windows", "android", "ios"]);

export interface Settings {
  projectUrl: string;
  publishableKey: string;
  email: string;
  password: string;
  desktopName: string | null;
}

/** A row of mox.current_file (§5). */
export interface Item {
  id: number;
  original_name: string;
  mime_type: string | null;
  size_bytes: number;
  kind: string;
  item_count: number;
  source_platform: string;
  source_device_id: string;
  uploaded_at: string;
}

/** Checks the rules of §5, so a bad row gets a clear message. */
export function validateItem(item: Item): Item {
  const fail = (reason: string): never => {
    throw new Error(`The current item in your project isn't valid: ${reason}.`);
  };
  if (item.id !== 1) fail("id must be 1");
  const nameLength = [...(item.original_name ?? "")].length;
  if (nameLength < 1 || nameLength > 255) fail("the name must be 1–255 characters");
  if (!(item.size_bytes >= 1 && item.size_bytes <= MAX_FILE_BYTES)) fail("the size must be 1 byte to 50 MB");
  const single = (item.kind === "file" || item.kind === "text") && item.item_count === 1;
  const bundle = item.kind === "bundle" && item.item_count >= 2;
  if (!single && !bundle) fail(`kind ${item.kind} can't have ${item.item_count} items`);
  if (!PLATFORMS.has(item.source_platform)) fail(`unknown platform ${item.source_platform}`);
  if (!item.source_device_id) fail("the sending device is missing");
  return item;
}

/** §6: act only on items from other devices that weren't handled yet. */
export function isNew(item: Item | null, deviceId: string, lastHandled: string | null): boolean {
  return item !== null && item.source_device_id !== deviceId && item.uploaded_at !== lastHandled;
}

/** The bytes of a text to send, or an error a person can act on. */
export function encodeText(text: string): Uint8Array {
  if (text.trim() === "") throw new Error("There's no text to send.");
  const bytes = new TextEncoder().encode(text);
  if (bytes.length > MAX_TEXT_BYTES) throw new Error("That text is too long: Mox sends texts up to 1 MB.");
  return bytes;
}

export function checkFileSize(size: number): void {
  if (size <= 0) throw new Error("The file is empty.");
  if (size > MAX_FILE_BYTES) throw new Error(`${humanSize(size)} is too big: Mox sends files up to 50 MB.`);
}

export function humanSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

/** The row that makes uploaded bytes the current item (§4.4). */
export function rowFor(name: string, mime: string, size: number, kind: "file" | "text", deviceId: string) {
  return {
    id: 1,
    original_name: name,
    mime_type: mime,
    size_bytes: size,
    kind,
    item_count: 1,
    source_platform: "ios",
    source_device_id: deviceId,
  };
}

/** "your Mac", "your Android phone"… for messages. */
export function sourceName(platform: string): string {
  return ({ macos: "your Mac", windows: "your PC", android: "your Android phone", ios: "your iPhone" } as Record<
    string,
    string
  >)[platform] ?? "another device";
}

/** VAPID keys arrive base64url-encoded; PushManager wants bytes. */
export function base64UrlToBytes(value: string): Uint8Array {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

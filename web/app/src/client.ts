// Talks to the owner's Supabase project over HTTPS (shared/PROTOCOL.md §2–§4).
// Same calls as the Mac and Android apps, with fetch instead of an SDK.
import { encodeText, type Item, rowFor, type Settings, TEXT_FILE_NAME, validateItem } from "./protocol.ts";

export class MoxClient {
  private token: string | null = null;
  private tokenExpiresAt = 0;
  private readonly base: string;

  constructor(private readonly settings: Settings, private readonly deviceId: string) {
    this.base = settings.projectUrl.replace(/\/$/, "");
  }

  /** §4.1: signs in and checks that this user owns Mox in the project. */
  async checkSchema(): Promise<void> {
    const rows = await this.json<{ schema_version: number }[]>("rest/v1/meta?select=schema_version", "GET");
    if (rows.length === 0) {
      throw new Error("This code is out of date. On your computer, open Mox, choose Set Up Again, and pair again.");
    }
    if (rows[0].schema_version !== 2) throw new Error("Your project and this app don't match. Set Mox up again.");
  }

  /** The key a device needs to subscribe to notifications, or null. */
  async vapidPublicKey(): Promise<string | null> {
    const rows = await this.json<{ vapid_public_key: string | null }[]>("rest/v1/meta?select=vapid_public_key", "GET");
    return rows[0]?.vapid_public_key ?? null;
  }

  async savePushSubscription(subscription: PushSubscription): Promise<void> {
    const json = subscription.toJSON();
    await this.json("rest/v1/push_subscriptions?on_conflict=endpoint", "POST", {
      endpoint: json.endpoint,
      p256dh: json.keys?.p256dh,
      auth: json.keys?.auth,
      device_id: this.deviceId,
    }, { Prefer: "resolution=merge-duplicates" });
  }

  /** §4.2: the item in the slot, or null when nothing was sent yet. */
  async current(): Promise<Item | null> {
    const rows = await this.json<Item[]>("rest/v1/current_file?id=eq.1&select=*", "GET");
    return rows.length ? validateItem(rows[0]) : null;
  }

  /** §4.5 + §4.6: downloads the current item. */
  async download(): Promise<Blob> {
    const reply = await this.json<{ signedURL: string }>("storage/v1/object/sign/mox/current", "POST", {
      expiresIn: 600,
    });
    const response = await fetch(`${this.base}/storage/v1${reply.signedURL}`);
    if (!response.ok) throw new Error(`Couldn't download it (HTTP ${response.status}).`);
    return response.blob();
  }

  async sendFile(file: File): Promise<Item> {
    const mime = file.type || "application/octet-stream";
    await this.upload(file, mime);
    return this.replaceRow(rowFor(file.name || "File", mime, file.size, "file", this.deviceId));
  }

  async sendText(text: string): Promise<Item> {
    const bytes = encodeText(text);
    await this.upload(new Blob([bytes as BlobPart], { type: "text/plain" }), "text/plain");
    return this.replaceRow(rowFor(TEXT_FILE_NAME, "text/plain", bytes.length, "text", this.deviceId));
  }

  // §4.3: bytes first, then the row, so no device sees a row without its bytes.
  private async upload(body: Blob, mime: string): Promise<void> {
    await this.request("storage/v1/object/mox/current", "POST", body, { "Content-Type": mime, "x-upsert": "true" });
  }

  private async replaceRow(row: object): Promise<Item> {
    const rows = await this.json<Item[]>("rest/v1/current_file?on_conflict=id", "POST", row, {
      Prefer: "resolution=merge-duplicates,return=representation",
    });
    return rows[0];
  }

  private async json<T>(path: string, method: string, body?: unknown, headers: Record<string, string> = {}) {
    const response = await this.request(
      path,
      method,
      body === undefined ? undefined : JSON.stringify(body),
      { "Content-Type": "application/json", ...headers },
    );
    const text = await response.text();
    return (text ? JSON.parse(text) : null) as T;
  }

  /** Every call with a valid token; on 401, signs in again and retries once. */
  private async request(path: string, method: string, body: BodyInit | undefined, headers: Record<string, string>) {
    for (const retry of [false, true]) {
      const token = await this.accessToken(retry);
      const profile = path.startsWith("rest/") ? { [method === "GET" ? "Accept-Profile" : "Content-Profile"]: "mox" } : {};
      const response = await fetch(`${this.base}/${path}`, {
        method,
        body,
        headers: { apikey: this.settings.publishableKey, Authorization: `Bearer ${token}`, ...profile, ...headers },
      });
      if (response.status === 401 && !retry) continue;
      if (!response.ok) throw new Error(`Supabase answered HTTP ${response.status}: ${(await response.text()).slice(0, 200)}`);
      return response;
    }
    throw new Error("Couldn't sign in to your project. Pair again from your computer.");
  }

  /** §2: each device signs in as the Mox user with its own session. */
  private async accessToken(renew: boolean): Promise<string> {
    if (this.token && !renew && this.tokenExpiresAt - Date.now() > 60_000) return this.token;
    const response = await fetch(`${this.base}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: { apikey: this.settings.publishableKey, "Content-Type": "application/json" },
      body: JSON.stringify({ email: this.settings.email, password: this.settings.password }),
    });
    if (!response.ok) throw new Error("This iPhone's pairing is out of date. On your computer, choose Pair a Phone.");
    const reply = await response.json() as { access_token: string; expires_in: number };
    this.token = reply.access_token;
    this.tokenExpiresAt = Date.now() + reply.expires_in * 1000;
    return this.token;
  }
}

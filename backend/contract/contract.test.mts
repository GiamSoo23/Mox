// Contract tests (#13): a real client against a real Supabase stack started
// by `supabase start`, with the migrations applied. Mocks pass even when the
// schema changes; this doesn't. It drives Mox for iPhone's own client, which
// makes the same calls as the Mac, Windows and Android apps (PROTOCOL.md §4).
//
//   eval "$(supabase status -o env)" && node --experimental-transform-types --test backend/contract/contract.test.mts
import { before, test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { MoxClient } from "../../web/app/src/client.ts";
import { readBundle } from "../../web/app/src/bundle.ts";

const env = (...names: string[]) => {
  const value = names.map((name) => process.env[name]).find(Boolean);
  if (!value) throw new Error(`Set ${names.join(" or ")} (eval "$(supabase status -o env)")`);
  return value;
};
const url = env("API_URL").replace(/\/$/, "");
const publishableKey = env("PUBLISHABLE_KEY", "ANON_KEY");
const secretKey = env("SECRET_KEY", "SERVICE_ROLE_KEY");
const dbUrl = env("DB_URL");
const fixtures = join(dirname(fileURLToPath(import.meta.url)), "../../shared/fixtures");

const owner = { email: `mox-${crypto.randomUUID()}@mox.invalid`, password: crypto.randomUUID() };
const stranger = { email: `other-${crypto.randomUUID()}@mox.invalid`, password: crypto.randomUUID() };
const deviceId = crypto.randomUUID();
const client = new MoxClient({ projectUrl: url, publishableKey, ...owner, desktopName: null }, deviceId);

/** Creates a confirmed user through the Auth admin API, as setup does. */
async function createUser(user: { email: string; password: string }): Promise<string> {
  const response = await fetch(`${url}/auth/v1/admin/users`, {
    method: "POST",
    headers: { apikey: secretKey, Authorization: `Bearer ${secretKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ ...user, email_confirm: true }),
  });
  assert.equal(response.status, 200, await response.clone().text());
  return ((await response.json()) as { id: string }).id;
}

async function signIn(user: { email: string; password: string }): Promise<string> {
  const response = await fetch(`${url}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: publishableKey, "Content-Type": "application/json" },
    body: JSON.stringify(user),
  });
  assert.equal(response.status, 200);
  return ((await response.json()) as { access_token: string }).access_token;
}

const headers = (token: string, extra: Record<string, string> = {}) => ({
  apikey: publishableKey,
  Authorization: `Bearer ${token}`,
  ...extra,
});

before(async () => {
  const id = await createUser(owner);
  await createUser(stranger);
  // The setup windows make this user the only one allowed in (Provisioner).
  execFileSync("psql", [dbUrl, "-X", "-q", "-v", "ON_ERROR_STOP=1", "-c",
    `update mox.meta set owner_id = '${id}' where id = 1; delete from mox.current_file;`]);
});

test("the owner passes the schema check (§4.1)", async () => {
  await client.checkSchema();
});

test("an empty slot reads as nothing (§4.2)", async () => {
  assert.equal(await client.current(), null);
});

test("a file goes up, its row reads back, and it downloads the same (§4.3–§4.6)", async () => {
  const bytes = new Uint8Array(4096).map((_, i) => i % 251);
  const sent = await client.sendFile(new File([bytes], "photo.jpg", { type: "image/jpeg" }));
  assert.equal(sent.original_name, "photo.jpg");
  assert.equal(sent.kind, "file");
  assert.equal(sent.size_bytes, bytes.length);
  assert.equal(sent.source_device_id, deviceId);

  const current = await client.current();
  assert.deepEqual(current, sent);
  assert.ok(Date.parse(current!.uploaded_at) > 0, "the database stamps uploaded_at");
  assert.deepEqual(new Uint8Array(await (await client.download()).arrayBuffer()), bytes);
});

test("a text replaces the file in the slot (#101)", async () => {
  const sent = await client.sendText("Hola 👋");
  assert.equal(sent.kind, "text");
  assert.equal(await (await client.download()).text(), "Hola 👋");
});

test("a bundle row is accepted and its zip unpacks after the round trip (§9)", async () => {
  const zip = readFileSync(join(fixtures, "bundles/valid/two-photos.zip"));
  const token = await signIn(owner);
  const upload = await fetch(`${url}/storage/v1/object/mox/current`, {
    method: "POST",
    headers: headers(token, { "Content-Type": "application/zip", "x-upsert": "true" }),
    body: zip,
  });
  assert.equal(upload.status, 200, await upload.clone().text());
  const row = await fetch(`${url}/rest/v1/current_file?on_conflict=id`, {
    method: "POST",
    headers: headers(token, {
      "Content-Type": "application/json",
      "Content-Profile": "mox",
      Prefer: "resolution=merge-duplicates,return=representation",
    }),
    body: JSON.stringify({
      id: 1, original_name: "Mox – 2 files.zip", mime_type: "application/zip", size_bytes: zip.length,
      kind: "bundle", item_count: 2, source_platform: "macos", source_device_id: crypto.randomUUID(),
    }),
  });
  // 201 when the row is new, 200 when it replaces the one already there.
  assert.ok([200, 201].includes(row.status), await row.clone().text());

  const current = await client.current();
  assert.equal(current?.kind, "bundle");
  assert.equal(current?.item_count, 2);
  const entries = await readBundle(new Uint8Array(await (await client.download()).arrayBuffer()));
  assert.deepEqual(entries.map((e) => e.path), ["IMG_0001.jpg", "IMG_0002.jpg"]);
});

test("the publishable key alone reads nothing", async () => {
  const rows = await fetch(`${url}/rest/v1/current_file?select=*`, {
    headers: { apikey: publishableKey, "Accept-Profile": "mox" },
  });
  assert.ok(rows.status === 401 || rows.status === 403 || (await rows.json()).length === 0);
  const sign = await fetch(`${url}/storage/v1/object/sign/mox/current`, {
    method: "POST",
    headers: { apikey: publishableKey, Authorization: `Bearer ${publishableKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ expiresIn: 60 }),
  });
  assert.notEqual(sign.status, 200);
});

test("another signed-in user can't read or replace the slot", async () => {
  const token = await signIn(stranger);
  const rows = await fetch(`${url}/rest/v1/current_file?select=*`, {
    headers: headers(token, { "Accept-Profile": "mox" }),
  });
  assert.deepEqual(await rows.json(), []);
  const upload = await fetch(`${url}/storage/v1/object/mox/current`, {
    method: "POST",
    headers: headers(token, { "Content-Type": "text/plain", "x-upsert": "true" }),
    body: "not yours",
  });
  assert.notEqual(upload.status, 200);
  assert.equal((await client.current())?.kind, "bundle", "the owner's item is still there");
});

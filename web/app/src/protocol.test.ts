// Runs Mox for iPhone's protocol rules against the shared fixtures, like
// the Mac, Android and database suites do.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { base64UrlToBytes, encodeText, isNew, type Item, MAX_TEXT_BYTES, rowFor, validateItem } from "./protocol.ts";

const rows = join(dirname(fileURLToPath(import.meta.url)), "../../../shared/fixtures/rows");
const load = (folder: string) =>
  readdirSync(join(rows, folder)).filter((f) => f.endsWith(".json"))
    .map((f) => [f, JSON.parse(readFileSync(join(rows, folder, f), "utf8")) as Item] as const);

for (const [file, row] of load("valid")) {
  test(`accepts rows/valid/${file}`, () => assert.doesNotThrow(() => validateItem(row)));
}
for (const [file, row] of load("invalid")) {
  test(`refuses rows/invalid/${file}`, () => assert.throws(() => validateItem(row)));
}

const item = load("valid").find(([f]) => f === "text-from-android.json")![1];

test("an item from another device that wasn't handled is new", () => {
  assert.equal(isNew(item, "my-device", null), true);
  assert.equal(isNew(item, "my-device", item.uploaded_at), false, "already handled");
  assert.equal(isNew(item, item.source_device_id, null), false, "sent by this device");
  assert.equal(isNew(null, "my-device", null), false, "empty slot");
});

test("texts must have content and stay under 1 MB", () => {
  assert.deepEqual(new TextDecoder().decode(encodeText("Hola 👋")), "Hola 👋");
  assert.throws(() => encodeText("  \n "));
  assert.throws(() => encodeText("a".repeat(MAX_TEXT_BYTES + 1)));
});

test("rows sent from the iPhone say so", () => {
  const row = rowFor("IMG_0001.HEIC", "image/heic", 10, "file", "d");
  assert.equal(row.source_platform, "ios");
  assert.doesNotThrow(() => validateItem({ ...row, source_device_id: "d", uploaded_at: "x" }));
});

test("VAPID keys decode from base64url", () => {
  assert.deepEqual([...base64UrlToBytes("AQID_-8")], [1, 2, 3, 255, 239]);
});

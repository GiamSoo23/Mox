// Runs Mox for iPhone's bundle reader against the shared fixtures, like the
// Mac, Android and Windows suites do.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { bundleName, checkBundleSize, readBundle, Refused, uniqueNames, writeBundle } from "./bundle.ts";

const bundles = join(dirname(fileURLToPath(import.meta.url)), "../../../shared/fixtures/bundles");
const zips = (folder: string) => readdirSync(join(bundles, folder)).filter((f) => f.endsWith(".zip")).sort();

for (const file of zips("valid")) {
  test(`unpacks bundles/valid/${file}`, async () => {
    const expected = JSON.parse(readFileSync(join(bundles, "valid", file.replace(/\.zip$/, ".json")), "utf8"));
    const entries = await readBundle(readFileSync(join(bundles, "valid", file)));
    assert.deepEqual(entries.map((e) => e.path), expected.files);
  });
}

test("refuses all nine invalid bundles", async () => {
  const files = zips("invalid");
  assert.equal(files.length, 9);
  for (const file of files) {
    await assert.rejects(readBundle(readFileSync(join(bundles, "invalid", file))), Refused, file);
  }
});

test("a file's name is the last part of its path", async () => {
  const entries = await readBundle(readFileSync(join(bundles, "valid", "folder-structure.zip")));
  assert.equal(entries[1].name, "day2.txt");
  assert.equal(new TextDecoder().decode(entries[1].data), "two");
});

const bytes = (text: string) => new TextEncoder().encode(text);

test("a written bundle reads back with the same files, in order", async () => {
  const files = [
    { name: "image.jpg", data: new Uint8Array(3000).map((_, i) => i % 256) },
    { name: "Año nuevo 🎉.txt", data: bytes("feliz") },
    { name: "empty.txt", data: new Uint8Array(0) },
  ];
  const entries = await readBundle(writeBundle(files));
  assert.deepEqual(entries.map((e) => e.path), files.map((f) => f.name));
  assert.deepEqual(entries.map((e) => [...e.data]), files.map((f) => [...f.data]));
});

test("a written bundle is stored, UTF-8, and made of regular files", () => {
  const zip = writeBundle([{ name: "a.txt", data: bytes("a") }, { name: "ñ.txt", data: bytes("b") }]);
  const view = new DataView(zip.buffer);
  assert.equal(view.getUint16(6, true) & 0x0800, 0x0800, "UTF-8 flag");
  assert.equal(view.getUint16(8, true), 0, "stored");
  const central = view.getUint32(zip.length - 6, true);
  assert.equal((view.getUint32(central + 38, true) >>> 16) & 0xf000, 0x8000, "regular file");
});

test("a bundle needs at least 2 files", () => {
  assert.throws(() => writeBundle([{ name: "a.txt", data: bytes("a") }]));
});

test("repeated names get a number, like the other apps", () => {
  assert.deepEqual(uniqueNames(["image.jpg", "image.jpg", "IMAGE.jpg", "notes", "notes", "a/b.txt"]),
    ["image.jpg", "image (1).jpg", "IMAGE (2).jpg", "notes", "notes (1)", "a_b.txt"]);
});

test("too big names the three biggest files", () => {
  const half = 52_428_800 / 2;
  assert.doesNotThrow(() => checkBundleSize([{ name: "a", size: half }, { name: "b", size: half }]));
  assert.throws(
    () => checkBundleSize([
      { name: "small.jpg", size: 1 }, { name: "big.mov", size: half }, { name: "bigger.mov", size: half + 1 },
    ]),
    /The biggest: bigger\.mov \(25 MB\), big\.mov \(25 MB\), small\.jpg/,
  );
});

test("the bundle name counts the files", () => assert.equal(bundleName(5), "Mox – 5 files.zip"));

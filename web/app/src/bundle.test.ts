// Runs Mox for iPhone's bundle reader against the shared fixtures, like the
// Mac, Android and Windows suites do.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { readBundle, Refused } from "./bundle.ts";

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

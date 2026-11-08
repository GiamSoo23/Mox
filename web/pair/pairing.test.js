// Runs the parser against the shared fixtures (shared/fixtures/pairing/).
// The same files are loaded by the macOS and Android test suites.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { PairingError, parsePairingLink } from "./pairing.js";

const fixtures = join(dirname(fileURLToPath(import.meta.url)), "../../shared/fixtures/pairing");
const read = (...p) => readFileSync(join(fixtures, ...p), "utf8").trim();
const links = (folder) => readdirSync(join(fixtures, folder)).filter((f) => f.endsWith(".txt"));

for (const file of links("valid")) {
  test(`accepts valid/${file}`, () => {
    const expected = JSON.parse(read("valid", file.replace(/\.txt$/, ".json")));
    assert.deepEqual(parsePairingLink(read("valid", file)), expected);
  });
}

for (const file of links("invalid")) {
  test(`refuses invalid/${file}`, () => {
    assert.throws(() => parsePairingLink(read("invalid", file)), PairingError);
  });
}

test("a secret key is refused with its own error code", () => {
  assert.throws(() => parsePairingLink(read("invalid", "secret-key.txt")), { code: "secret-key" });
});

test("a newer link version asks for an update", () => {
  assert.throws(() => parsePairingLink(read("invalid", "future-version.txt")), { code: "unsupported-version" });
});

test("malformed percent-encoding is a PairingError, not a crash", () => {
  assert.throws(() => parsePairingLink("https://x.test/#v=1&u=%E0%A4%A"), { code: "bad-encoding" });
});

test("there are fixtures to test", () => {
  assert.ok(links("valid").length >= 6 && links("invalid").length >= 12);
});

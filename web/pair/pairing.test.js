// Runs the parser against the shared fixtures (shared/fixtures/pairing/).
// The same files are loaded by the macOS and Android test suites.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { PairingError, androidIntentUrl, cameBackWithoutApp, parsePairingLink } from "./pairing.js";

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

const PAGE = "https://giamsoo23.github.io/Mox/pair/";

test("Open in Mox falls back to the pairing page, not to a download", () => {
  const url = androidIntentUrl("v=1&p=secret", `${PAGE}#v=1&p=secret`);
  assert.ok(url.startsWith("intent://pair?v=1&p=secret#Intent;scheme=mox;package=com.mox.app;"));
  const fallback = decodeURIComponent(url.match(/S\.browser_fallback_url=([^;]*);end$/)[1]);
  assert.equal(fallback, `${PAGE}?app=missing#v=1&p=secret`);
  assert.ok(!fallback.includes(".apk"));
});

test("the parameters stay in the fragment after coming back", () => {
  const url = androidIntentUrl("v=1&p=secret", `${PAGE}?app=missing#v=1&p=secret`);
  const fallback = new URL(decodeURIComponent(url.match(/S\.browser_fallback_url=([^;]*);end$/)[1]));
  assert.equal(fallback.search, "?app=missing");
  assert.equal(fallback.hash, "#v=1&p=secret");
});

test("the page knows when the browser came back without the app", () => {
  assert.equal(cameBackWithoutApp(`${PAGE}?app=missing#v=1`), true);
  assert.equal(cameBackWithoutApp(`${PAGE}#v=1`), false);
});

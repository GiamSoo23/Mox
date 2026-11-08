// Parses a Mox pairing link (shared/PROTOCOL.md §8). No DOM, no network:
// the same module runs in the browser and in Node's test runner.

export const SUPPORTED_VERSION = "1";

/** A pairing link that can't be used. `code` is stable; `message` is for people. */
export class PairingError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "PairingError";
    this.code = code;
  }
}

const REQUIRED = ["v", "u", "k", "e", "p"];
const HANDOFF_PREFIX = "mox://pair?";

/** The raw `key=value&…` string of either link form, untouched. */
export function extractParams(link) {
  const text = String(link).trim();
  if (text.startsWith(HANDOFF_PREFIX)) return text.slice(HANDOFF_PREFIX.length);
  const hash = text.indexOf("#");
  if (hash === -1 || hash === text.length - 1) {
    throw new PairingError("no-parameters", "This pairing link is incomplete. Scan the QR code again.");
  }
  return text.slice(hash + 1);
}

function decode(value) {
  // decodeURIComponent never turns "+" into a space, as §8.2 requires.
  try {
    return decodeURIComponent(value);
  } catch {
    throw new PairingError("bad-encoding", "This pairing link is damaged. Scan the QR code again.");
  }
}

/** Validates raw parameters and returns the configuration they describe. */
export function parsePairingParams(raw) {
  if (!raw) throw new PairingError("no-parameters", "This pairing link is incomplete. Scan the QR code again.");

  const params = new Map();
  for (const part of raw.split("&")) {
    if (part === "") continue;
    const eq = part.indexOf("=");
    const key = eq === -1 ? part : part.slice(0, eq);
    const value = eq === -1 ? "" : part.slice(eq + 1);
    if (params.has(key)) throw new PairingError("duplicate-key", `This pairing link repeats "${key}".`);
    params.set(key, decode(value));
  }

  for (const key of REQUIRED) {
    if (!params.get(key)) {
      throw new PairingError(`missing-${key}`, "This pairing link is incomplete. Scan the QR code again.");
    }
  }

  if (params.get("v") !== SUPPORTED_VERSION) {
    throw new PairingError("unsupported-version", "This link needs a newer version of Mox. Update the app and scan again.");
  }

  let projectUrl = params.get("u");
  if (projectUrl.endsWith("/")) projectUrl = projectUrl.slice(0, -1);
  if (!/^https:\/\/[A-Za-z0-9.-]+(:\d+)?$/.test(projectUrl)) {
    throw new PairingError("bad-project-url", "The project address in this link isn't valid.");
  }

  const key = params.get("k");
  if (key.startsWith("sb_secret_")) {
    // Never store or display it. A secret key must not reach a phone.
    throw new PairingError("secret-key", "This link contains a secret key, which must never be shared. Use the project's publishable key instead.");
  }
  if (!key.startsWith("sb_publishable_")) {
    throw new PairingError("bad-key", "This link doesn't contain a publishable key.");
  }

  const email = params.get("e");
  if (email.split("@").length !== 2 || email.length > 254) {
    throw new PairingError("bad-email", "The Mox user in this link isn't valid.");
  }

  const password = params.get("p");
  if (password.length < 16 || password.length > 128) {
    throw new PairingError("bad-password", "The Mox user's password in this link isn't valid.");
  }

  const name = params.get("n") || null;
  if (name !== null && [...name].length > 64) {
    throw new PairingError("name-too-long", "The computer name in this link is too long.");
  }

  return {
    version: Number(SUPPORTED_VERSION),
    projectUrl,
    publishableKey: key,
    email,
    password,
    desktopName: name,
  };
}

/** Parses either form of the link (https pairing link or mox:// hand-off). */
export function parsePairingLink(link) {
  return parsePairingParams(extractParams(link));
}

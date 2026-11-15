// Reads a bundle: several files sent as one zip (shared/PROTOCOL.md §9).
// It refuses the whole bundle when any entry breaks a rule.

export const MAX_ENTRIES = 1000;
export const MAX_UNPACKED = 52_428_800;

export interface Entry {
  path: string;
  name: string;
  data: Uint8Array<ArrayBuffer>;
}

export class Refused extends Error {
  constructor(reason: string) {
    super(`Mox didn't unpack these files: ${reason}.`);
  }
}

interface Record {
  name: string;
  method: number;
  crc: number;
  compressedSize: number;
  size: number;
  external: number;
  localHeader: number;
}

/** The files in a bundle, in order, or throws Refused. */
export async function readBundle(zip: Uint8Array): Promise<Entry[]> {
  const records = centralDirectory(zip);
  if (records.length > MAX_ENTRIES) throw new Refused("it has too many files");
  const kept: Record[] = [];
  let total = 0;
  for (const record of records) {
    check(record.name, record.external);
    if (isSkipped(record.name)) continue;
    total += record.size;
    if (total > MAX_UNPACKED) throw new Refused("they add up to more than 50 MB");
    kept.push(record);
  }
  if (kept.length < 2) throw new Refused("a bundle has at least 2 files");
  const entries: Entry[] = [];
  for (const record of kept) {
    entries.push({ path: record.name, name: record.name.split("/").pop()!, data: await contents(record, zip) });
  }
  return entries;
}

const TYPES: { [ext: string]: string } = {
  jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", heic: "image/heic", gif: "image/gif", webp: "image/webp",
  mov: "video/quicktime", mp4: "video/mp4", pdf: "application/pdf", txt: "text/plain", zip: "application/zip",
};

/** The type to give a file from its name, so iPhone offers "Save Images" for photos. */
export const typeFor = (name: string) => TYPES[name.split(".").pop()?.toLowerCase() ?? ""] ?? "application/octet-stream";

function check(name: string, external: number) {
  if (name.includes("\\") || name.startsWith("/") || name[1] === ":" || name.split("/").includes("..")) {
    throw new Refused(`“${name}” points outside the folder`);
  }
  if (((external >>> 16) & 0xf000) === 0xa000) throw new Refused(`“${name}” is a link`);
}

const isSkipped = (name: string) =>
  name.endsWith("/") || name.startsWith("__MACOSX/") || name.split("/").pop() === ".DS_Store";

function centralDirectory(zip: Uint8Array): Record[] {
  const view = new DataView(zip.buffer, zip.byteOffset, zip.byteLength);
  const notZip = new Refused("it isn't a zip");
  if (zip.length < 22) throw notZip;
  const lowest = Math.max(0, zip.length - 22 - 65_535);
  let end = zip.length - 22;
  while (end >= lowest && view.getUint32(end, true) !== 0x06054b50) end--;
  if (end < lowest) throw notZip;
  const count = view.getUint16(end + 10, true);
  let offset = view.getUint32(end + 16, true);
  const utf8 = new TextDecoder("utf-8", { fatal: true });
  const records: Record[] = [];
  for (let i = 0; i < count; i++) {
    if (offset + 46 > zip.length || view.getUint32(offset, true) !== 0x02014b50) throw notZip;
    const nameLength = view.getUint16(offset + 28, true);
    if (offset + 46 + nameLength > zip.length) throw notZip;
    let name: string;
    try {
      name = utf8.decode(zip.subarray(offset + 46, offset + 46 + nameLength));
    } catch {
      throw notZip;
    }
    records.push({
      name,
      method: view.getUint16(offset + 10, true),
      crc: view.getUint32(offset + 16, true),
      compressedSize: view.getUint32(offset + 20, true),
      size: view.getUint32(offset + 24, true),
      external: view.getUint32(offset + 38, true),
      localHeader: view.getUint32(offset + 42, true),
    });
    offset += 46 + nameLength + view.getUint16(offset + 30, true) + view.getUint16(offset + 32, true);
  }
  return records;
}

async function contents(record: Record, zip: Uint8Array): Promise<Uint8Array<ArrayBuffer>> {
  const view = new DataView(zip.buffer, zip.byteOffset, zip.byteLength);
  const damaged = new Refused(`“${record.name}” is damaged`);
  const header = record.localHeader;
  if (header + 30 > zip.length || view.getUint32(header, true) !== 0x04034b50) throw damaged;
  const start = header + 30 + view.getUint16(header + 26, true) + view.getUint16(header + 28, true);
  if (start + record.compressedSize > zip.length) throw damaged;
  const stored = zip.slice(start, start + record.compressedSize);
  let data: Uint8Array<ArrayBuffer>;
  if (record.method === 0) {
    data = stored;
  } else if (record.method === 8) {
    data = await inflate(stored, record.size).catch(() => {
      throw damaged;
    });
  } else {
    throw new Refused(`“${record.name}” uses a compression Mox doesn't read`);
  }
  if (data.length !== record.size || crc32(data) !== record.crc) throw damaged;
  return data;
}

/** Raw deflate, stopping as soon as the output passes the declared size. */
async function inflate(input: Uint8Array<ArrayBuffer>, size: number): Promise<Uint8Array<ArrayBuffer>> {
  const stream = new Blob([input]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
  const reader = stream.getReader();
  const out = new Uint8Array(size);
  let written = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    if (written + value.length > size) {
      await reader.cancel();
      throw new Error("bigger than declared");
    }
    out.set(value, written);
    written += value.length;
  }
  if (written !== size) throw new Error("smaller than declared");
  return out;
}

let table: Uint32Array | undefined;

function crc32(data: Uint8Array): number {
  table ??= Uint32Array.from({ length: 256 }, (_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
  });
  let crc = 0xffffffff;
  for (const byte of data) crc = table[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

// ---- Writing ----------------------------------------------------------------

/** "Mox – 5 files.zip", the name the row carries. */
export const bundleName = (count: number) => `Mox – ${count} files.zip`;

/**
 * Names that don't repeat, keeping the order: iPhone often calls every picked
 * photo "image.jpg", so the second becomes "image (1).jpg", like the other apps.
 */
export function uniqueNames(names: string[]): string[] {
  const taken = new Set<string>();
  return names.map((original) => {
    const name = original.replace(/[/\\]/g, "_") || "File";
    const dot = name.lastIndexOf(".");
    const [stem, ext] = dot > 0 ? [name.slice(0, dot), name.slice(dot)] : [name, ""];
    let candidate = name;
    for (let n = 1; taken.has(candidate.toLowerCase()); n++) candidate = `${stem} (${n})${ext}`;
    taken.add(candidate.toLowerCase());
    return candidate;
  });
}

const megabytes = (bytes: number) => `${(bytes / 1_048_576).toFixed(1).replace(/\.0$/, "")} MB`;

/** Throws before reading anything when the files add up to more than 50 MB, naming the 3 biggest. */
export function checkBundleSize(files: { name: string; size: number }[]): void {
  const total = files.reduce((sum, file) => sum + file.size, 0);
  if (total <= MAX_UNPACKED) return;
  const biggest = [...files].sort((a, b) => b.size - a.size).slice(0, 3)
    .map((file) => `${file.name} (${megabytes(file.size)})`).join(", ");
  throw new Error(`These files add up to ${megabytes(total)}, and Mox sends up to 50 MB. The biggest: ${biggest}.`);
}

/** An uncompressed zip with UTF-8 names, as §9 asks. Names must already be unique. */
export function writeBundle(files: { name: string; data: Uint8Array }[]): Uint8Array<ArrayBuffer> {
  if (files.length < 2) throw new Error("A bundle has at least 2 files.");
  const utf8 = new TextEncoder();
  const named = files.map((file) => ({ ...file, encoded: utf8.encode(file.name), crc: crc32(file.data) }));
  const local = named.reduce((sum, f) => sum + 30 + f.encoded.length + f.data.length, 0);
  const central = named.reduce((sum, f) => sum + 46 + f.encoded.length, 0);
  const zip = new Uint8Array(local + central + 22);
  const view = new DataView(zip.buffer);
  const { time, date } = dosTime(new Date());
  let offset = 0;
  const headers: number[] = [];
  for (const f of named) {
    headers.push(offset);
    view.setUint32(offset, 0x04034b50, true);
    view.setUint16(offset + 4, 20, true); // version needed
    view.setUint16(offset + 6, 0x0800, true); // names are UTF-8
    view.setUint16(offset + 8, 0, true); // stored
    view.setUint16(offset + 10, time, true);
    view.setUint16(offset + 12, date, true);
    view.setUint32(offset + 14, f.crc, true);
    view.setUint32(offset + 18, f.data.length, true);
    view.setUint32(offset + 22, f.data.length, true);
    view.setUint16(offset + 26, f.encoded.length, true);
    zip.set(f.encoded, offset + 30);
    zip.set(f.data, offset + 30 + f.encoded.length);
    offset += 30 + f.encoded.length + f.data.length;
  }
  const start = offset;
  named.forEach((f, i) => {
    view.setUint32(offset, 0x02014b50, true);
    view.setUint16(offset + 4, (3 << 8) | 20, true); // made by Unix, so the mode below counts
    view.setUint16(offset + 6, 20, true);
    view.setUint16(offset + 8, 0x0800, true);
    view.setUint16(offset + 12, time, true);
    view.setUint16(offset + 14, date, true);
    view.setUint32(offset + 16, f.crc, true);
    view.setUint32(offset + 20, f.data.length, true);
    view.setUint32(offset + 24, f.data.length, true);
    view.setUint16(offset + 28, f.encoded.length, true);
    view.setUint32(offset + 38, 0o100644 << 16 >>> 0, true); // a regular file
    view.setUint32(offset + 42, headers[i], true);
    zip.set(f.encoded, offset + 46);
    offset += 46 + f.encoded.length;
  });
  view.setUint32(offset, 0x06054b50, true);
  view.setUint16(offset + 8, named.length, true);
  view.setUint16(offset + 10, named.length, true);
  view.setUint32(offset + 12, offset - start, true);
  view.setUint32(offset + 16, start, true);
  return zip;
}

function dosTime(now: Date) {
  return {
    time: (now.getHours() << 11) | (now.getMinutes() << 5) | (now.getSeconds() >> 1),
    date: ((Math.max(now.getFullYear(), 1980) - 1980) << 9) | ((now.getMonth() + 1) << 5) | now.getDate(),
  };
}

// Rules for what the Send to Mox shortcut uploads (#27). No network here,
// so they're tested on their own.

export const MAX_FILE_BYTES = 52_428_800;
export const MAX_TEXT_BYTES = 1_000_000;

const TYPES: Record<string, string> = {
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    png: "image/png",
    heic: "image/heic",
    heif: "image/heif",
    gif: "image/gif",
    webp: "image/webp",
    mov: "video/quicktime",
    mp4: "video/mp4",
    m4v: "video/x-m4v",
    pdf: "application/pdf",
    txt: "text/plain",
    zip: "application/zip",
};

/** The file's type, from what iPhone says or else from its extension. */
export function mimeFor(name: string, given: string | null | undefined): string {
    if (given && given !== "application/octet-stream") return given;
    const extension = name.includes(".") ? name.split(".").pop()!.toLowerCase() : "";
    return TYPES[extension] ?? "application/octet-stream";
}

/** A name the database accepts: 1 to 255 characters. */
export function cleanName(name: string | null | undefined): string {
    const trimmed = (name ?? "").trim();
    return trimmed === "" ? "File" : [...trimmed].slice(0, 255).join("");
}

export interface Upload {
    bytes: Uint8Array;
    name: string;
    mime: string;
    kind: "file" | "text";
}

/** What to upload, from the shortcut's form: a `file` or a `text` field. */
export async function uploadFrom(form: FormData): Promise<Upload> {
    const file = form.get("file");
    const text = form.get("text");
    if (file instanceof File) {
        if (file.size <= 0) throw new UserError("The file is empty.");
        if (file.size > MAX_FILE_BYTES) throw new UserError("That file is over 50 MB, the most Mox sends.");
        const name = cleanName(file.name);
        return { bytes: new Uint8Array(await file.arrayBuffer()), name, mime: mimeFor(name, file.type), kind: "file" };
    }
    if (typeof text === "string" && text.trim() !== "") {
        const bytes = new TextEncoder().encode(text);
        if (bytes.length > MAX_TEXT_BYTES) throw new UserError("That text is over 1 MB, the most Mox sends.");
        return { bytes, name: "Text.txt", mime: "text/plain", kind: "text" };
    }
    throw new UserError("There's nothing to send.");
}

/** An error whose message is meant for the person using the shortcut. */
export class UserError extends Error {}

export interface Credentials {
    key: string;
    email: string;
    password: string;
    device: string;
}

/**
 * The Mox user's credentials from the request. The shortcut sends the setup
 * code as one header (`x-mox-setup`, a JSON object), because that's the least
 * it can build by hand. Four separate headers still work.
 */
export function credentialsFrom(headers: Headers): Credentials {
    const setup = headers.get("x-mox-setup");
    if (setup) {
        try {
            const parsed = JSON.parse(setup);
            return {
                key: String(parsed.key ?? ""),
                email: String(parsed.email ?? ""),
                password: String(parsed.password ?? ""),
                device: String(parsed.device ?? ""),
            };
        } catch {
            throw new UserError("The shortcut's setup code isn't valid. Copy a new one in Mox for iPhone.");
        }
    }
    return {
        key: headers.get("x-mox-key") ?? "",
        email: headers.get("x-mox-email") ?? "",
        password: headers.get("x-mox-password") ?? "",
        device: headers.get("x-mox-device") ?? "",
    };
}

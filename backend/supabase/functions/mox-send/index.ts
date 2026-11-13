// Sends a file or text from the Send to Mox shortcut on iPhone (#27).
// Shortcuts can't easily sign in and make three requests, so it makes one,
// here, in the user's own project. This function signs in as the Mox user
// with the credentials the request carries and uses that session, so the
// same row level security applies as for every Mox app.
import { credentialsFrom, type Upload, uploadFrom, uploadFromBody, UserError } from "./send.ts";

const PROJECT = Deno.env.get("SUPABASE_URL") ?? "";

Deno.serve(async (request) => {
    if (request.method !== "POST") return reply("Use POST.", 405);
    try {
        const { key, email, password, device } = credentialsFrom(request.headers);
        const token = await signIn(key, email, password);
        const type = request.headers.get("content-type") ?? "";
        const body = type.startsWith("multipart/form-data") ? null : new Uint8Array(await request.arrayBuffer());
        // Running the shortcut by itself, with nothing shared, checks the setup.
        if (body !== null && body.length === 0) return reply("Mox is ready. Share a photo or file to send it.", 200);
        const upload = body === null
            ? await uploadFrom(await request.formData())
            : uploadFromBody(body, request.headers.get("x-mox-name"), type);
        await send(upload, key, token, device);
        return reply(upload.kind === "text" ? "Text sent to Mox." : `Sent ${upload.name} to Mox.`, 200);
    } catch (error) {
        const message = error instanceof UserError ? error.message : "Mox couldn't send it. Try again.";
        if (!(error instanceof UserError)) console.error(error);
        return reply(message, error instanceof UserError ? 400 : 500);
    }
});

function reply(message: string, status: number) {
    return Response.json({ message }, { status });
}

async function signIn(key: string, email: string, password: string): Promise<string> {
    const response = await fetch(`${PROJECT}/auth/v1/token?grant_type=password`, {
        method: "POST",
        headers: { apikey: key, "Content-Type": "application/json" },
        body: JSON.stringify({ email, password }),
    });
    if (!response.ok) {
        throw new UserError("The shortcut's setup code is out of date. Copy a new one in Mox for iPhone.");
    }
    return (await response.json()).access_token;
}

// PROTOCOL.md §4.3 then §4.4: bytes first, then the row.
async function send(upload: Upload, key: string, token: string, device: string) {
    const auth = { apikey: key, Authorization: `Bearer ${token}` };
    const stored = await fetch(`${PROJECT}/storage/v1/object/mox/current`, {
        method: "POST",
        headers: { ...auth, "Content-Type": upload.mime, "x-upsert": "true" },
        body: new Blob([upload.bytes as BlobPart], { type: upload.mime }),
    });
    if (!stored.ok) throw new Error(`storage answered ${stored.status}: ${await stored.text()}`);
    const row = await fetch(`${PROJECT}/rest/v1/current_file?on_conflict=id`, {
        method: "POST",
        headers: {
            ...auth,
            "Content-Type": "application/json",
            "Content-Profile": "mox",
            Prefer: "resolution=merge-duplicates",
        },
        body: JSON.stringify({
            id: 1,
            original_name: upload.name,
            mime_type: upload.mime,
            size_bytes: upload.bytes.length,
            kind: upload.kind,
            item_count: 1,
            source_platform: "ios",
            source_device_id: device,
        }),
    });
    if (!row.ok) throw new Error(`the database answered ${row.status}: ${await row.text()}`);
}

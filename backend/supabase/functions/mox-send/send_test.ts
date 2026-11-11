import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { cleanName, credentialsFrom, MAX_TEXT_BYTES, mimeFor, uploadFrom, UserError } from "./send.ts";

Deno.test("the type comes from iPhone, or else from the extension", () => {
    assertEquals(mimeFor("IMG_0001.HEIC", ""), "image/heic");
    assertEquals(mimeFor("clip.MOV", "application/octet-stream"), "video/quicktime");
    assertEquals(mimeFor("photo.jpg", "image/png"), "image/png");
    assertEquals(mimeFor("notes", null), "application/octet-stream");
});

Deno.test("names are never empty or too long", () => {
    assertEquals(cleanName("  "), "File");
    assertEquals([...cleanName("a".repeat(300))].length, 255);
});

Deno.test("a file field becomes a file", async () => {
    const form = new FormData();
    form.set("file", new File([new Uint8Array([1, 2, 3])], "IMG_0001.jpg"));
    const upload = await uploadFrom(form);
    assertEquals([upload.kind, upload.name, upload.mime, upload.bytes.length], [
        "file",
        "IMG_0001.jpg",
        "image/jpeg",
        3,
    ]);
});

Deno.test("a text field becomes a text", async () => {
    const form = new FormData();
    form.set("text", "Hola 👋");
    const upload = await uploadFrom(form);
    assertEquals([upload.kind, upload.name, upload.mime], ["text", "Text.txt", "text/plain"]);
});

Deno.test("empty or oversized input is refused with a clear message", async () => {
    await assertRejects(() => uploadFrom(new FormData()), UserError);
    const empty = new FormData();
    empty.set("file", new File([], "empty.txt"));
    await assertRejects(() => uploadFrom(empty), UserError);
    const long = new FormData();
    long.set("text", "a".repeat(MAX_TEXT_BYTES + 1));
    await assertRejects(() => uploadFrom(long), UserError);
});

Deno.test("the setup code arrives as one JSON header", () => {
    const headers = new Headers({
        "x-mox-setup": JSON.stringify({ url: "u", key: "k", email: "e", password: "p", device: "d" }),
    });
    assertEquals(credentialsFrom(headers), { key: "k", email: "e", password: "p", device: "d" });
});

Deno.test("separate headers still work, and a broken setup code is explained", () => {
    const headers = new Headers({ "x-mox-key": "k", "x-mox-email": "e", "x-mox-password": "p", "x-mox-device": "d" });
    assertEquals(credentialsFrom(headers).email, "e");
    try {
        credentialsFrom(new Headers({ "x-mox-setup": "{not json" }));
        throw new Error("should have thrown");
    } catch (error) {
        assertEquals(error instanceof UserError, true);
    }
});

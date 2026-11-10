import { assertEquals } from "jsr:@std/assert@1";
import { notificationFor, sameSecret } from "./notification.ts";

const item = {
    kind: "file",
    name: "IMG_0001.jpg",
    item_count: 1,
    source_platform: "macos",
    uploaded_at: "2026-11-11T12:00:00Z",
};

Deno.test("a file from the Mac", () => {
    const n = notificationFor(item);
    assertEquals(n.title, "New file from your Mac");
    assertEquals(n.body, "IMG_0001.jpg · tap to open");
    assertEquals(n.uploadedAt, item.uploaded_at);
});

Deno.test("a text says it can be copied", () => {
    const n = notificationFor({ ...item, kind: "text", source_platform: "android" });
    assertEquals(n.title, "Text from your Android phone");
    assertEquals(n.body, "Tap to copy it.");
});

Deno.test("a bundle counts its files", () => {
    assertEquals(notificationFor({ ...item, kind: "bundle", item_count: 5 }).title, "5 files from your Mac");
});

Deno.test("the secret must match exactly", () => {
    assertEquals(sameSecret("abc", "abc"), true);
    assertEquals(sameSecret("abd", "abc"), false);
    assertEquals(sameSecret(null, "abc"), false);
    assertEquals(sameSecret("abc", undefined), false);
});

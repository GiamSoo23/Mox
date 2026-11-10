// What a push says about a new item (#54). No network here, so it's tested
// on its own.

export interface Item {
    kind: string;
    name: string;
    item_count: number;
    source_platform: string;
    uploaded_at: string;
}

export interface Notification {
    title: string;
    body: string;
    kind: string;
    uploadedAt: string;
}

const PLATFORMS: Record<string, string> = {
    macos: "your Mac",
    windows: "your PC",
    android: "your Android phone",
    ios: "your iPhone",
};

export function notificationFor(item: Item): Notification {
    const from = PLATFORMS[item.source_platform] ?? "another device";
    const title = item.kind === "text"
        ? `Text from ${from}`
        : item.kind === "bundle"
        ? `${item.item_count} files from ${from}`
        : `New file from ${from}`;
    const body = item.kind === "text" ? "Tap to copy it." : `${item.name} · tap to open`;
    return { title, body, kind: item.kind, uploadedAt: item.uploaded_at };
}

/** Constant-time comparison for the shared secret. */
export function sameSecret(given: string | null, expected: string | undefined): boolean {
    if (!given || !expected || given.length !== expected.length) return false;
    let difference = 0;
    for (let i = 0; i < given.length; i++) difference |= given.charCodeAt(i) ^ expected.charCodeAt(i);
    return difference === 0;
}

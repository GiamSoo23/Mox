// Sends Web Push notifications when the slot changes (#54). Called only by
// the database trigger mox.notify_push(), which passes the subscriptions,
// so this function never reads the database. Secrets, set by setup:
// MOX_PUSH_SECRET, MOX_VAPID_PUBLIC_KEY, MOX_VAPID_PRIVATE_KEY.
import webpush from "npm:web-push@3.6.7";
import { type Item, notificationFor, sameSecret } from "./notification.ts";

interface Subscription {
    endpoint: string;
    keys: { p256dh: string; auth: string };
}

webpush.setVapidDetails(
    "https://github.com/GiamSoo23/Mox",
    Deno.env.get("MOX_VAPID_PUBLIC_KEY") ?? "",
    Deno.env.get("MOX_VAPID_PRIVATE_KEY") ?? "",
);

Deno.serve(async (request) => {
    if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
    if (!sameSecret(request.headers.get("x-mox-secret"), Deno.env.get("MOX_PUSH_SECRET"))) {
        return new Response("Forbidden", { status: 403 });
    }
    const { subscriptions, item } = await request.json() as { subscriptions: Subscription[]; item: Item };
    const payload = JSON.stringify(notificationFor(item));
    const results = await Promise.allSettled(
        subscriptions.map((subscription) =>
            webpush.sendNotification(subscription, payload, { TTL: 3600, urgency: "high" })
        ),
    );
    const failed = results.filter((result) => result.status === "rejected").length;
    return Response.json({ sent: results.length - failed, failed });
});

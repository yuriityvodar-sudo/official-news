// Notifications received (Yurii, 27 Nov 2026): the server sends to FCM topics,
// so it never knows how many phones a notification reached. Each phone says
// "one arrived" when it does (Android: the app's message handler; iPhone: its
// notification service extension), with the notification's language and the
// platform only: no id or token, so the count is anonymous (privacy policy,
// privacyNotificationsCount). One row a day per language and platform.
import type { Env } from "../env";
import { LANGS } from "../translator/languages";

const PLATFORMS = ["ios", "android"];
const PUSH_LANGS: readonly string[] = ["en", ...LANGS];

/** `POST /v1/push/delivered` with `{ lang, platform }`: 204, or 400 for anything else. */
export async function pushDelivered(body: unknown, env: Env, now = new Date()): Promise<{ status: number; body?: unknown }> {
  const b = body as { lang?: unknown; platform?: unknown } | null;
  if (!b || typeof b.lang !== "string" || !PUSH_LANGS.includes(b.lang) || typeof b.platform !== "string" || !PLATFORMS.includes(b.platform)) {
    return { status: 400, body: { error: "Expected { lang, platform }" } };
  }
  await env.DB.prepare(
    `INSERT INTO push_delivered (day, lang, platform, received) VALUES (?1, ?2, ?3, 1)
     ON CONFLICT (day, lang, platform) DO UPDATE SET received = received + 1`,
  )
    .bind(now.toISOString().slice(0, 10), b.lang, b.platform)
    .run();
  return { status: 204 };
}

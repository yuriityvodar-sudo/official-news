// Notifications received, counted with no id (Yurii, 27 Nov 2026).
import { env, exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { pushDelivered } from "../src/push/delivered";

const rows = () =>
  env.DB.prepare("SELECT day, lang, platform, received FROM push_delivered ORDER BY lang, platform").all().then((r) => r.results);

describe("POST /v1/push/delivered", () => {
  it("adds one per notification received, by day, language and platform", async () => {
    const day = new Date("2026-11-27T10:00:00Z");
    await pushDelivered({ lang: "uk", platform: "android" }, env, day);
    await pushDelivered({ lang: "uk", platform: "android" }, env, day);
    await pushDelivered({ lang: "en", platform: "ios" }, env, day);
    await pushDelivered({ lang: "uk", platform: "android" }, env, new Date("2026-11-28T00:01:00Z"));
    expect(await rows()).toEqual([
      { day: "2026-11-27", lang: "en", platform: "ios", received: 1 },
      { day: "2026-11-27", lang: "uk", platform: "android", received: 2 },
      { day: "2026-11-28", lang: "uk", platform: "android", received: 1 },
    ]);
  });

  it("takes only a language and a platform it knows, and nothing that identifies the phone", async () => {
    for (const body of [null, {}, { lang: "xx", platform: "ios" }, { lang: "en", platform: "web" }, { lang: "en" }]) {
      expect((await pushDelivered(body, env)).status).toBe(400);
    }
    expect(await rows()).toEqual([]);
    const columns = await env.DB.prepare("SELECT name FROM pragma_table_info('push_delivered')").all<{ name: string }>();
    expect(columns.results.map((c) => c.name)).toEqual(["day", "lang", "platform", "received"]);
  });

  it("answers 204 through the API, and 405 to a GET", async () => {
    const post = await exports.default.fetch("https://api.test/v1/push/delivered", { method: "POST", body: JSON.stringify({ lang: "es", platform: "android" }) });
    expect(post.status).toBe(204);
    expect((await exports.default.fetch("https://api.test/v1/push/delivered")).status).toBe(405);
  });
});

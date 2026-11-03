// The admin page's daily report (#60, Yurii 3 Nov, after LyFi's): windows
// ending yesterday in Kyiv, each against the one before, and the funnel from
// Google Search and the website to the App Store build.
import { env as workers } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import type { AdminEnv } from "../src/admin/env";
import { dailyReport, kyivDate, windowDates } from "../src/admin/report";

describe("the report's days", () => {
  it("end yesterday in Kyiv, also just after midnight there", () => {
    // 22:30 UTC on 2 Nov is 00:30 on 3 Nov in Kyiv (UTC+2): yesterday is 2 Nov.
    const now = new Date("2026-11-02T22:30:00Z");
    expect(kyivDate(now)).toBe("2026-11-03");
    const d = windowDates(now);
    expect(d.day).toEqual({ now: { start: "2026-11-02", end: "2026-11-02" }, before: { start: "2026-11-01", end: "2026-11-01" } });
    expect(d.week).toEqual({ now: { start: "2026-10-27", end: "2026-11-02" }, before: { start: "2026-10-20", end: "2026-10-26" } });
    expect(d.month.now).toEqual({ start: "2026-10-04", end: "2026-11-02" });
    expect(d.month.before).toEqual({ start: "2026-09-04", end: "2026-10-03" });
  });
});

/** Google's answers: each GA report's rows by its date ranges and filter, and Search Console by date, query or page. */
function google(): { fetcher: typeof fetch; asked: string[] } {
  const asked: string[] = [];
  const row = (key: string[], values: number[]) => ({ dimensionValues: key.map((value) => ({ value })), metricValues: values.map((v) => ({ value: String(v) })) });
  const fetcher = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    asked.push(url.replace(/\?.*/, ""));
    if (url === "https://oauth2.googleapis.com/token") return Response.json({ access_token: "t", expires_in: 3600 });
    const body = JSON.parse(String(init?.body ?? "{}"));
    if (url.includes(":batchRunReports")) {
      const reports = (body.requests as { dateRanges: { name?: string }[]; dimensions?: { name: string }[]; dimensionFilter: unknown }[]).map((r) => {
        const where = JSON.stringify(r.dimensionFilter);
        if (r.dimensions?.[0]?.name === "firstUserSourceMedium") return { rows: [row(["google / organic"], [40])] };
        const values = (name: string) => {
          const now = name.endsWith("_now");
          if (where.includes("app_store_click")) return now ? [12, 9] : [6, 5];
          if (where.includes('"web"')) return now ? [300, 200, 360, 900] : [200, 150, 240, 600];
          if (where.includes("customUser:build")) return now ? [30, 6, 60, 5400] : [20, 4, 40, 3600];
          return now ? [50, 10, 100, 9000] : [40, 8, 80, 7200];
        };
        return { rows: r.dateRanges.map((d) => row([d.name!], values(d.name!))) };
      });
      return Response.json({ reports });
    }
    if (url.includes("searchconsole.googleapis.com")) {
      if (body.dimensions[0] === "date") {
        const rows = [];
        for (let t = Date.parse(body.startDate); t <= Date.parse(body.endDate); t += 86_400_000) {
          rows.push({ keys: [new Date(t).toISOString().slice(0, 10)], clicks: 10, impressions: 200, position: 8 });
        }
        return Response.json({ rows });
      }
      if (body.dimensions[0] === "query") return Response.json({ rows: [{ keys: ["czech fuel price cap"], clicks: 7, impressions: 90, position: 3 }] });
      return Response.json({ rows: [{ keys: ["https://outernews.app/en/cz/01J-fuel"], clicks: 7, impressions: 90, position: 3 }] });
    }
    return new Response("unexpected", { status: 500 });
  }) as typeof fetch;
  return { fetcher, asked };
}

describe("the daily report", () => {
  it("shows the funnel, Google Search, the website and the app, each window against the one before", async () => {
    const { privateKey } = (await crypto.subtle.generateKey(
      { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
      true,
      ["sign", "verify"],
    )) as CryptoKeyPair;
    // A key generated here, never one of ours.
    const pk = (await crypto.subtle.exportKey("pkcs8", privateKey)) as ArrayBuffer;
    const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...new Uint8Array(pk)))}\n-----END PRIVATE KEY-----\n`;
    const env = {
      DB: workers.DB,
      GA_PROPERTY: "123",
      ACCESS_TEAM: "t",
      ACCESS_AUD: "a",
      ADMIN_EMAILS: "y@example.com",
      GA_CLIENT_EMAIL: "r@x.iam.gserviceaccount.com",
      ASC_KEY_ID: "K",
      ASC_ISSUER_ID: "I",
      GA_SERVICE_ACCOUNT: JSON.stringify({ client_email: "r@x.iam.gserviceaccount.com", private_key: pem, project_id: "x" }),
      ADMIN_KV: { get: async () => null, put: async () => undefined } as unknown as KVNamespace,
    } as AdminEnv;
    const { fetcher, asked } = google();
    const html = await dailyReport(env, fetcher, new Date("2026-11-03T10:00:00Z"));
    expect(html).toContain("Days end yesterday, 2026-11-02, Kyiv time.");
    // Funnel: 300 visitors, 9 of them clicked App Store (3.0%), 6 new App Store users; +50% against 200.
    expect(html).toMatch(/Website visitors \(people\)<\/td><td class="n">300<\/td><td class="n"><span class="up">\+50%<\/span>/);
    expect(html).toMatch(/Clicked App Store \(people\)<\/td><td class="n">9<\/td>/);
    expect(html).toMatch(/Clicked, % of visitors<\/td><td class="n">3\.0<\/td>/);
    expect(html).toMatch(/New App Store users \(first opens\)<\/td><td class="n">6<\/td>/);
    // Google Search: 10 clicks a day, 70 a week, 300 a month; position 8.0, unchanged.
    expect(html).toMatch(/Clicks to the site<\/td><td class="n">10<\/td><td class="n"><span class="up">\+0%<\/span><\/td><td class="n">70<\/td>/);
    expect(html).toMatch(/Average position<\/td><td class="n">8\.0<\/td>/);
    // The website, with its App Store clicks counted as times.
    expect(html).toMatch(/App Store clicks \(times\)<\/td><td class="n">12<\/td><td class="n"><span class="up">\+100%<\/span>/);
    // The app: sessions per user and minutes per user worked out from Google's totals.
    expect(html).toMatch(/Sessions per active user<\/td><td class="n">2\.0<\/td>/);
    expect(html).toMatch(/Minutes per active user<\/td><td class="n">3\.0<\/td>/);
    expect(html).toContain("czech fuel price cap");
    expect(html).toContain("/en/cz/01J-fuel");
    expect(html).toContain("google / organic");
    // Two GA batches, the build's two reports apart, and three Search Console queries.
    expect(asked.filter((u) => u.includes(":batchRunReports"))).toHaveLength(4);
    expect(asked.filter((u) => u.includes("searchconsole"))).toHaveLength(3);
  });
});

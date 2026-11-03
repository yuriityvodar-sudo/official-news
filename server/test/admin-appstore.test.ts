// Apple's numbers in the admin page (#60): App Store Connect's daily reports
// read once each and summed per day, only our app's first-time downloads, and
// what came from the website's buttons (ct=web-…) or from outernews.app.
import { describe, expect, it } from "vitest";
import { APP_ID, appleDays, fromWebsite, sumDays, sumRows, syncApple, type AppleDay } from "../src/admin/appstore";
import type { AdminEnv } from "../src/admin/env";

function memoryKv() {
  const store = new Map<string, string>();
  return {
    store,
    kv: {
      get: async (key: string, type?: string) => {
        const v = store.get(key);
        return v === undefined ? null : type === "json" ? JSON.parse(v) : v;
      },
      put: async (key: string, value: string) => void store.set(key, value),
    } as unknown as KVNamespace,
  };
}

const DOWNLOADS = [
  "Date\tApp Name\tApp Apple Identifier\tDownload Type\tSource Type\tSource Info\tCampaign\tTerritory\tCounts",
  `2026-11-10\tOuter News\t${APP_ID}\tFirst-time download\tWeb referrer\touternews.app\t\tCZ\t3`,
  `2026-11-10\tOuter News\t${APP_ID}\tFirst-time download\tApp Store search\t\t\tUA\t5`,
  `2026-11-10\tOuter News\t${APP_ID}\tFirst-time download\tWeb referrer\t\tweb-article-uk\tUA\t2`,
  `2026-11-10\tOuter News\t${APP_ID}\tRedownload\tApp Store search\t\t\tUA\t4`,
  `2026-11-10\tSola Bible\t6806792931\tFirst-time download\tApp Store search\t\t\tUS\t9`,
].join("\n");
const ENGAGEMENT = [
  "Date\tApp Apple Identifier\tEvent\tPage Type\tSource Type\tCounts",
  `2026-11-10\t${APP_ID}\tImpression\tSearch\tApp Store search\t100`,
  `2026-11-10\t${APP_ID}\tPage view\tProduct page\tWeb referrer\t12`,
  `2026-11-10\t${APP_ID}\tPage view\tProduct page\tApp Store search\t20`,
].join("\n");

const rows = (tsv: string) => {
  const [head, ...lines] = tsv.split("\n");
  const names = head.split("\t").map((n) => n.toLowerCase());
  return lines.map((l) => Object.fromEntries(l.split("\t").map((v, i) => [names[i], v])));
};

describe("summing Apple's rows", () => {
  it("counts only our app's first-time downloads, by source, campaign and referring site, and page views apart from impressions", () => {
    const days = new Map<string, AppleDay>();
    sumRows("downloads", rows(DOWNLOADS), days);
    sumRows("engagement", rows(ENGAGEMENT), days);
    const day = days.get("2026-11-10")!;
    expect(day.downloads).toBe(10);
    expect(day.downloadsBySource).toEqual({ "Web referrer": 5, "App Store search": 5 });
    expect(day.downloadsByCampaign).toEqual({ "web-article-uk": 2 });
    expect(day.downloadsByWeb).toEqual({ "outernews.app": 3, "(none)": 2 });
    expect(fromWebsite(day.downloadsByCampaign) + fromWebsite(day.downloadsByWeb)).toBe(5);
    expect(day.impressions).toBe(100);
    expect(day.pageViews).toBe(32);
    expect(day.pageViewsBySource["Web referrer"]).toBe(12);
  });
});

describe("reading App Store Connect", () => {
  it("makes the report request once, reads each daily instance once, and keeps the days", async () => {
    // A key generated here, never one of ours.
    const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
    const pk = (await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer;
    const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...new Uint8Array(pk)))}\n-----END PRIVATE KEY-----\n`;
    const { kv, store } = memoryKv();
    const env = { ASC_KEY_ID: "KEY1", ASC_ISSUER_ID: "ISSUER", ASC_PRIVATE_KEY: pem, ADMIN_KV: kv } as unknown as AdminEnv;
    const gz = async (text: string) => new Response(new Blob([text]).stream().pipeThrough(new CompressionStream("gzip"))).arrayBuffer();
    const calls: string[] = [];
    const fetcher = (async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      calls.push(`${init?.method ?? "GET"} ${url.replace("https://api.appstoreconnect.apple.com/v1", "")}`);
      if (url.startsWith("https://api.appstoreconnect.apple.com")) {
        const auth = new Headers(init?.headers).get("authorization")!;
        const [head, body, sig] = auth.slice(7).split(".");
        const b64 = (s: string) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
        expect(JSON.parse(new TextDecoder().decode(b64(head)))).toEqual({ alg: "ES256", kid: "KEY1", typ: "JWT" });
        expect(JSON.parse(new TextDecoder().decode(b64(body)))).toMatchObject({ iss: "ISSUER", aud: "appstoreconnect-v1" });
        expect(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pair.publicKey, b64(sig), new TextEncoder().encode(`${head}.${body}`))).toBe(true);
      }
      if (url.endsWith(`/apps/${APP_ID}/analyticsReportRequests?filter[accessType]=ONGOING`)) return Response.json({ data: [] });
      if (url.endsWith("/analyticsReportRequests") && init?.method === "POST") return Response.json({ data: { id: "REQ1" } });
      if (url.includes("/analyticsReportRequests/REQ1/reports")) {
        return Response.json({ data: [{ id: url.includes("Downloads") ? "R-DL" : "R-EN" }] });
      }
      if (url.endsWith("/analyticsReports/R-DL/instances?filter[granularity]=DAILY")) return Response.json({ data: [{ id: "I-DL" }] });
      if (url.endsWith("/analyticsReports/R-EN/instances?filter[granularity]=DAILY")) return Response.json({ data: [{ id: "I-EN" }] });
      if (url.endsWith("/analyticsReportInstances/I-DL/segments")) return Response.json({ data: [{ id: "S1", attributes: { url: "https://files.test/dl.gz" } }] });
      if (url.endsWith("/analyticsReportInstances/I-EN/segments")) return Response.json({ data: [{ id: "S2", attributes: { url: "https://files.test/en.gz" } }] });
      if (url === "https://files.test/dl.gz") return new Response(await gz(DOWNLOADS));
      if (url === "https://files.test/en.gz") return new Response(await gz(ENGAGEMENT));
      return new Response(JSON.stringify({ errors: [{ detail: "unexpected" }] }), { status: 404 });
    }) as typeof fetch;

    const first = await syncApple(env, fetcher, new Date("2026-11-12T08:00:00Z"));
    expect(first).toEqual({ request: "REQ1", reports: { downloads: "R-DL", engagement: "R-EN" }, instancesRead: 2, error: null });
    expect(calls.filter((c) => c.startsWith("POST"))).toEqual(["POST /analyticsReportRequests"]);
    const days = await appleDays(env, "2026-11-09", "2026-11-11");
    expect(sumDays(days, "2026-11-10", "2026-11-10")).toMatchObject({ downloads: 10, pageViews: 32, impressions: 100 });

    // The next time: no new request, no instance read twice, the same numbers.
    calls.length = 0;
    const second = await syncApple(env, fetcher, new Date("2026-11-12T09:00:00Z"));
    expect(second.instancesRead).toBe(0);
    expect(calls.some((c) => c.includes("segments") || c.startsWith("POST") || c.includes("/apps/"))).toBe(false);
    expect(JSON.parse(store.get("asc-day:2026-11-10")!).downloads).toBe(10);
  });

  it("says what is missing, and never throws, without a key or when Apple refuses", async () => {
    const { kv } = memoryKv();
    expect((await syncApple({ ADMIN_KV: kv } as unknown as AdminEnv)).error).toBe("No App Store Connect key yet.");
    const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
    const pk = (await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer;
    const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...new Uint8Array(pk)))}\n-----END PRIVATE KEY-----\n`;
    const refused = (async () => new Response(JSON.stringify({ errors: [{ detail: "The API key in use does not allow this request" }] }), { status: 403 })) as unknown as typeof fetch;
    const status = await syncApple({ ADMIN_KV: kv, ASC_KEY_ID: "K", ASC_ISSUER_ID: "I", ASC_PRIVATE_KEY: pem } as unknown as AdminEnv, refused);
    expect(status.error).toBe("App Store Connect: HTTP 403 The API key in use does not allow this request");
  });
});

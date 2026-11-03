// Apple's own numbers for the funnel (#60, Yurii 3 Nov): App Store Connect's
// Analytics Reports, read with the key "Outer News Reports" (docs/setup.md).
// Apple never tells the app who installed from where; these reports count, per
// day, the App Store page views and the first-time downloads by where they came
// from: the website's campaign (`ct=web-…`, site/stores.ts), a web referrer,
// search, browse. One ongoing report request for the app (made once, then
// kept), Apple builds its daily instances a day or two late; each instance is
// read once, its rows for our app summed per day into ADMIN_KV.
import { base64url, pemToDer } from "../push/fcm";
import type { AdminEnv } from "./env";

/** Outer News in the App Store (docs/setup.md). */
export const APP_ID = "6822820350";
const API = "https://api.appstoreconnect.apple.com/v1";

/** The two daily reports read: downloads by source and campaign, and page views and impressions. */
export const REPORTS = { downloads: "App Downloads Standard", engagement: "App Store Discovery and Engagement Standard" } as const;
type ReportKind = keyof typeof REPORTS;

/** One day's numbers from Apple, summed over the report instances read so far. */
export interface AppleDay {
  /** First-time downloads: all, by source type, by campaign, by referring website. */
  downloads: number;
  downloadsBySource: Record<string, number>;
  downloadsByCampaign: Record<string, number>;
  downloadsByWeb: Record<string, number>;
  /** Product page views and impressions: all, and page views by source type and campaign (when the report gives one). */
  pageViews: number;
  impressions: number;
  pageViewsBySource: Record<string, number>;
  pageViewsByCampaign: Record<string, number>;
}

const emptyDay = (): AppleDay => ({
  downloads: 0,
  downloadsBySource: {},
  downloadsByCampaign: {},
  downloadsByWeb: {},
  pageViews: 0,
  impressions: 0,
  pageViewsBySource: {},
  pageViewsByCampaign: {},
});

let signingKey: { pem: string; key: CryptoKey } | undefined;

/** A token for App Store Connect's API: ES256, the key's id, our issuer, 15 minutes. */
async function token(env: AdminEnv, now: Date): Promise<string> {
  if (!env.ASC_PRIVATE_KEY) throw new Error("No App Store Connect key yet (ASC_PRIVATE_KEY)");
  if (signingKey?.pem !== env.ASC_PRIVATE_KEY) {
    signingKey = {
      pem: env.ASC_PRIVATE_KEY,
      key: await crypto.subtle.importKey("pkcs8", pemToDer(env.ASC_PRIVATE_KEY), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]),
    };
  }
  const iat = Math.floor(now.getTime() / 1000);
  const text = (value: unknown) => base64url(new TextEncoder().encode(JSON.stringify(value)));
  const head = `${text({ alg: "ES256", kid: env.ASC_KEY_ID, typ: "JWT" })}.${text({ iss: env.ASC_ISSUER_ID, iat, exp: iat + 900, aud: "appstoreconnect-v1" })}`;
  // WebCrypto's ECDSA signature is r‖s, as JWT's ES256 wants.
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, signingKey.key, new TextEncoder().encode(head));
  return `${head}.${base64url(new Uint8Array(signature))}`;
}

type Doc = { data: { id: string; attributes?: Record<string, unknown> }[] | { id: string } };

async function asc(env: AdminEnv, fetcher: typeof fetch, path: string, jwt: string, body?: unknown): Promise<Doc> {
  const response = await fetcher(`${API}${path}`, {
    method: body ? "POST" : "GET",
    headers: { authorization: `Bearer ${jwt}`, ...(body ? { "content-type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = (await response.json().catch(() => null)) as (Doc & { errors?: { detail?: string; title?: string }[] }) | null;
  if (!response.ok || !json) throw new Error(`App Store Connect: HTTP ${response.status} ${json?.errors?.[0]?.detail ?? json?.errors?.[0]?.title ?? ""}`.trim());
  return json;
}
const list = (doc: Doc) => (Array.isArray(doc.data) ? doc.data : []);

const KV = { request: "asc-request", reports: "asc-reports", day: (date: string) => `asc-day:${date}`, done: (id: string) => `asc-done:${id}` };

/** Gzipped TSV to rows of named columns. */
async function tsvRows(gzipped: ArrayBuffer): Promise<Record<string, string>[]> {
  const text = await new Response(new Blob([gzipped]).stream().pipeThrough(new DecompressionStream("gzip"))).text();
  const [head, ...lines] = text.split(/\r?\n/).filter(Boolean);
  const names = (head ?? "").split("\t").map((n) => n.trim().toLowerCase());
  return lines.map((line) => Object.fromEntries(line.split("\t").map((v, i) => [names[i], v.trim()])));
}

const add = (map: Record<string, number>, key: string | undefined, n: number) => {
  const k = key && key !== "" ? key : "(none)";
  map[k] = (map[k] ?? 0) + n;
};

/**
 * Sums one instance's rows into its days: only our app's rows, and for
 * downloads only first-time ones (not redownloads or updates). Column names as
 * Apple's reports have them, matched without case.
 */
export function sumRows(kind: ReportKind, rows: Record<string, string>[], days: Map<string, AppleDay>): void {
  for (const row of rows) {
    const app = row["app apple identifier"];
    if (app && app !== APP_ID) continue;
    const date = row["date"];
    if (!date) continue;
    const day = days.get(date) ?? emptyDay();
    days.set(date, day);
    const n = Number(row["counts"]) || 0;
    if (kind === "downloads") {
      if (!/first[- ]time/i.test(row["download type"] ?? "")) continue;
      day.downloads += n;
      add(day.downloadsBySource, row["source type"], n);
      if (row["campaign"]) add(day.downloadsByCampaign, row["campaign"], n);
      if (/web/i.test(row["source type"] ?? "")) add(day.downloadsByWeb, row["source info"], n);
    } else {
      const event = (row["event"] ?? "").toLowerCase();
      if (event.includes("impression")) day.impressions += n;
      else if (event.includes("page view")) {
        day.pageViews += n;
        add(day.pageViewsBySource, row["source type"], n);
        if (row["campaign"]) add(day.pageViewsByCampaign, row["campaign"], n);
      }
    }
  }
}

/** What reading Apple's reports found: for the Downloads tab. */
export interface AppleStatus {
  request: string | null;
  reports: Partial<Record<ReportKind, string>>;
  instancesRead: number;
  error: string | null;
}

/**
 * Makes sure the ongoing report request exists, then reads up to `max` daily
 * instances not read yet and sums them into ADMIN_KV. Never throws: the
 * report shows the error instead.
 */
export async function syncApple(env: AdminEnv, fetcher: typeof fetch = fetch, now = new Date(), max = 6): Promise<AppleStatus> {
  const status: AppleStatus = { request: null, reports: {}, instancesRead: 0, error: null };
  if (!env.ASC_PRIVATE_KEY) return { ...status, error: "No App Store Connect key yet." };
  try {
    const jwt = await token(env, now);
    let request = await env.ADMIN_KV.get(KV.request);
    if (!request) {
      const found = list(await asc(env, fetcher, `/apps/${APP_ID}/analyticsReportRequests?filter[accessType]=ONGOING`, jwt));
      request =
        found[0]?.id ??
        ((
          await asc(env, fetcher, "/analyticsReportRequests", jwt, {
            data: { type: "analyticsReportRequests", attributes: { accessType: "ONGOING" }, relationships: { app: { data: { type: "apps", id: APP_ID } } } },
          })
        ).data as { id: string }).id;
      await env.ADMIN_KV.put(KV.request, request);
    }
    status.request = request;
    const reports = (await env.ADMIN_KV.get<Partial<Record<ReportKind, string>>>(KV.reports, "json")) ?? {};
    for (const kind of Object.keys(REPORTS) as ReportKind[]) {
      if (reports[kind]) continue;
      const found = list(await asc(env, fetcher, `/analyticsReportRequests/${request}/reports?filter[name]=${encodeURIComponent(REPORTS[kind])}`, jwt));
      if (found[0]) reports[kind] = found[0].id;
    }
    await env.ADMIN_KV.put(KV.reports, JSON.stringify(reports));
    status.reports = reports;
    const days = new Map<string, AppleDay>();
    const read: string[] = [];
    for (const kind of Object.keys(reports) as ReportKind[]) {
      const instances = list(await asc(env, fetcher, `/analyticsReports/${reports[kind]}/instances?filter[granularity]=DAILY`, jwt));
      for (const instance of instances) {
        if (read.length >= max) break;
        if (await env.ADMIN_KV.get(KV.done(instance.id))) continue;
        for (const segment of list(await asc(env, fetcher, `/analyticsReportInstances/${instance.id}/segments`, jwt))) {
          const url = segment.attributes?.url;
          if (typeof url !== "string") continue;
          const file = await fetcher(url);
          if (!file.ok) throw new Error(`App Store Connect: a report file answered HTTP ${file.status}`);
          sumRows(kind, await tsvRows(await file.arrayBuffer()), days);
        }
        read.push(instance.id);
      }
    }
    for (const [date, day] of days) {
      const old = (await env.ADMIN_KV.get<AppleDay>(KV.day(date), "json")) ?? emptyDay();
      await env.ADMIN_KV.put(KV.day(date), JSON.stringify(merge(old, day)));
    }
    for (const id of read) await env.ADMIN_KV.put(KV.done(id), "1");
    status.instancesRead = read.length;
  } catch (error) {
    status.error = String(error instanceof Error ? error.message : error).replace(/[<>&]/g, "");
  }
  return status;
}

function merge(a: AppleDay, b: AppleDay): AppleDay {
  const maps = (x: Record<string, number>, y: Record<string, number>) => {
    const out = { ...x };
    for (const [k, v] of Object.entries(y)) out[k] = (out[k] ?? 0) + v;
    return out;
  };
  return {
    downloads: a.downloads + b.downloads,
    downloadsBySource: maps(a.downloadsBySource, b.downloadsBySource),
    downloadsByCampaign: maps(a.downloadsByCampaign, b.downloadsByCampaign),
    downloadsByWeb: maps(a.downloadsByWeb, b.downloadsByWeb),
    pageViews: a.pageViews + b.pageViews,
    impressions: a.impressions + b.impressions,
    pageViewsBySource: maps(a.pageViewsBySource, b.pageViewsBySource),
    pageViewsByCampaign: maps(a.pageViewsByCampaign, b.pageViewsByCampaign),
  };
}

/** The stored days from `start` to `end` (UTC, as Apple's), each read once. */
export async function appleDays(env: AdminEnv, start: string, end: string): Promise<Map<string, AppleDay>> {
  const dates: string[] = [];
  for (let t = Date.parse(`${start}T00:00:00Z`); t <= Date.parse(`${end}T00:00:00Z`); t += 86_400_000) dates.push(new Date(t).toISOString().slice(0, 10));
  const days = await Promise.all(dates.map((d) => env.ADMIN_KV.get<AppleDay>(KV.day(d), "json")));
  return new Map(dates.flatMap((d, i) => (days[i] ? [[d, days[i]!] as [string, AppleDay]] : [])));
}

/** The days of a range summed; null when none is stored. */
export function sumDays(days: Map<string, AppleDay>, start: string, end: string): AppleDay | null {
  let total: AppleDay | null = null;
  for (const [date, day] of days) if (date >= start && date <= end) total = merge(total ?? emptyDay(), day);
  return total;
}

/** From the website: the campaigns of our buttons (`web…`) and Safari's or any site's referral from outernews.app. */
export const fromWebsite = (map: Record<string, number>) => Object.entries(map).reduce((s, [k, v]) => s + (/^web/.test(k) || /outernews\.app/.test(k) ? v : 0), 0);

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const top = (map: Record<string, number>) =>
  Object.entries(map)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10);

/** The Downloads tab: what Apple reported for the last 30 days, with where downloads and page views came from. */
export async function downloadsTab(env: AdminEnv, fetcher: typeof fetch = fetch, now = new Date()): Promise<string> {
  const status = await syncApple(env, fetcher, now);
  const end = new Date(now.getTime() - 86_400_000).toISOString().slice(0, 10);
  const start = new Date(now.getTime() - 30 * 86_400_000).toISOString().slice(0, 10);
  const days = await appleDays(env, start, end);
  const total = sumDays(days, start, end);
  const state = `<p class="note">Report request ${status.request ? esc(status.request) : "not made yet"}; reports found: ${
    Object.keys(status.reports).length ? Object.keys(status.reports).map((k) => REPORTS[k as ReportKind]).join(", ") : "none yet"
  }; read now: ${status.instancesRead} new.${status.error ? ` Apple said: ${status.error}` : ""} Days are UTC; Apple reports a day or two late.</p>`;
  if (!total) return `<section style="margin-top:20px"><h2>Downloads</h2><p class="muted">No day reported by Apple yet: the first reports come a day or two after the request, and Outer News's numbers start at its release.</p>${state}</section>`;
  const table = (title: string, rows: [string, number][]) =>
    `<section><h2>${esc(title)}</h2>${
      rows.length
        ? `<table><tbody>${rows.map(([k, v]) => `<tr><td>${esc(k)}</td><td class="n">${v.toLocaleString("en-US")}</td></tr>`).join("")}</tbody></table>`
        : '<p class="muted">None.</p>'
    }</section>`;
  const byDay = [...days.entries()].sort((a, b) => b[0].localeCompare(a[0]));
  return `<div class="cards"><div class="card"><p>First-time downloads, 30 days</p><b>${total.downloads.toLocaleString("en-US")}</b></div><div class="card"><p>Product page views</p><b>${total.pageViews.toLocaleString("en-US")}</b></div><div class="card"><p>Impressions</p><b>${total.impressions.toLocaleString("en-US")}</b></div><div class="card"><p>Downloads from the website</p><b>${(fromWebsite(total.downloadsByCampaign) + fromWebsite(total.downloadsByWeb)).toLocaleString("en-US")}</b></div></div>
<div class="grid">
${table("Downloads by source", top(total.downloadsBySource))}
${table("Downloads by campaign (website buttons: web-…)", top(total.downloadsByCampaign))}
${table("Downloads by referring website", top(total.downloadsByWeb))}
${table("Page views by source", top(total.pageViewsBySource))}
<section><h2>By day</h2><table><thead><tr><th></th><th>Downloads</th><th>Page views</th></tr></thead><tbody>${byDay
    .map(([d, v]) => `<tr><td>${d}</td><td class="n">${v.downloads}</td><td class="n">${v.pageViews}</td></tr>`)
    .join("")}</tbody></table></section>
</div>${state}`;
}

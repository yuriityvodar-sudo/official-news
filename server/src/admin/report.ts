// The daily report (#60, Yurii 3 Nov), after LyFi's: the funnel from Google
// and the website to the App Store and the app, each number for yesterday
// against the day before, the last 7 days against the 7 before and the last 30
// against the 30 before. Days end yesterday in Kyiv time. Numbers come from
// Google Analytics (the website and the app, one property), Search Console
// (Google Search) and, once there is a key, App Store Connect (the store).
import type { AdminEnv } from "./env";
import { type Request as Report, type Rows, batch, googlePost, single } from "./ga";
import { esc } from "./page";

/** The three windows, each ending yesterday: its length in days. */
export const WINDOWS = [
  { id: "day", days: 1, label: "Yesterday" },
  { id: "week", days: 7, label: "Last 7 days" },
  { id: "month", days: 30, label: "Last 30 days" },
] as const;
type WindowId = (typeof WINDOWS)[number]["id"];

const DAY_MS = 86_400_000;

/** Kyiv's date `back` days before `now`, as YYYY-MM-DD. */
export function kyivDate(now: Date, back = 0): string {
  const today = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Kyiv", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
  return new Date(Date.parse(`${today}T00:00:00Z`) - back * DAY_MS).toISOString().slice(0, 10);
}

/** Each window's dates: `now` ends yesterday; `before` is as long, just before it. */
export function windowDates(now: Date) {
  return Object.fromEntries(
    WINDOWS.map((w) => [
      w.id,
      { now: { start: kyivDate(now, w.days), end: kyivDate(now, 1) }, before: { start: kyivDate(now, 2 * w.days), end: kyivDate(now, w.days + 1) } },
    ]),
  ) as Record<WindowId, { now: { start: string; end: string }; before: { start: string; end: string } }>;
}

/** A window's two numbers. */
type Pair = { now: number; before: number };
/** Each window's pairs, per metric. */
type Block = Record<WindowId, Pair[]>;

const filter = (...pairs: [string, string | string[]][]) => ({
  andGroup: {
    expressions: pairs.map(([fieldName, value]) => ({
      filter: Array.isArray(value) ? { fieldName, inListFilter: { values: value } } : { fieldName, stringFilter: { value } },
    })),
  },
});
const WEB = filter(["platform", "web"]);
const CLICKS = filter(["platform", "web"], ["eventName", "app_store_click"]);
const APP = filter(["platform", ["iOS", "Android"]]);
const STORE = filter(["platform", ["iOS", "Android"]], ["customUser:build", "store"]);

/**
 * The two reports of one block (GA takes at most 4 date ranges a report):
 * yesterday and the week with the days before them, then the month. Users
 * are counted per range by Google, never summed from days.
 */
function reports(dates: ReturnType<typeof windowDates>, where: object, metrics: string[]): [Report, Report] {
  const r = (id: WindowId) => [
    { startDate: dates[id].now.start, endDate: dates[id].now.end, name: `${id}_now` },
    { startDate: dates[id].before.start, endDate: dates[id].before.end, name: `${id}_before` },
  ];
  const report = (ranges: object[]): Report => ({ dateRanges: ranges, metrics: metrics.map((name) => ({ name })), dimensionFilter: where });
  return [report([...r("day"), ...r("week")]), report(r("month"))];
}

/** A block from its two reports: each window's now and before, per metric; zeros where Google has no row. */
function block(a: Rows | null, b: Rows | null, metrics: number): Block {
  const value = (name: string, i: number) => [...(a?.rows ?? []), ...(b?.rows ?? [])].find((row) => row.key[0] === name)?.values[i] ?? 0;
  return Object.fromEntries(
    WINDOWS.map((w) => [w.id, Array.from({ length: metrics }, (_, i) => ({ now: value(`${w.id}_now`, i), before: value(`${w.id}_before`, i) }))]),
  ) as Block;
}

const SEARCH = "https://searchconsole.googleapis.com/webmasters/v3/sites/sc-domain%3Aouternews.app/searchAnalytics/query";
type SearchRow = { keys?: string[]; clicks: number; impressions: number; position: number };

/** Google Search per window from one query by date: clicks, impressions, click rate and position (weighted by impressions). */
function searchBlock(rows: SearchRow[], dates: ReturnType<typeof windowDates>): Block {
  const sum = (range: { start: string; end: string }) => {
    const inRange = rows.filter((r) => r.keys![0] >= range.start && r.keys![0] <= range.end);
    const clicks = inRange.reduce((s, r) => s + r.clicks, 0);
    const impressions = inRange.reduce((s, r) => s + r.impressions, 0);
    const position = impressions ? inRange.reduce((s, r) => s + r.position * r.impressions, 0) / impressions : 0;
    return [clicks, impressions, impressions ? (100 * clicks) / impressions : 0, position];
  };
  return Object.fromEntries(
    WINDOWS.map((w) => {
      const now = sum(dates[w.id].now);
      const before = sum(dates[w.id].before);
      return [w.id, now.map((n, i) => ({ now: n, before: before[i] }))];
    }),
  ) as Block;
}

const num = (n: number, digits = 0) => (digits ? n.toFixed(digits) : Math.round(n).toLocaleString("en-US"));

/** The change against before, coloured by whether it is better (`lowerIsBetter` for a search position). */
function delta(p: Pair, lowerIsBetter = false): string {
  if (!p.before) return p.now ? '<span class="muted">new</span>' : "";
  const pct = Math.round(((p.now - p.before) / p.before) * 100);
  const better = lowerIsBetter ? pct <= 0 : pct >= 0;
  return `<span class="${better ? "up" : "down"}">${pct >= 0 ? "+" : ""}${pct}%</span>`;
}

interface Line {
  label: string;
  /** Index into the block's metrics, or a value worked out from them. */
  value: number | ((m: Pair[], side: "now" | "before") => number);
  digits?: number;
  lowerIsBetter?: boolean;
}

/** A table: one row per line, then each window with its change. */
function table(title: string, b: Block | null, lines: Line[], note = ""): string {
  if (!b) return `<section><h2>${esc(title)}</h2><p class="muted">${note || "Not available yet."}</p></section>`;
  const head = WINDOWS.map((w) => `<th>${w.label}</th><th></th>`).join("");
  const body = lines
    .map((line) => {
      const cells = WINDOWS.map((w) => {
        const m = b[w.id];
        const p = typeof line.value === "number" ? m[line.value] : { now: line.value(m, "now"), before: line.value(m, "before") };
        return `<td class="n">${num(p.now, line.digits)}</td><td class="n">${delta(p, line.lowerIsBetter)}</td>`;
      }).join("");
      return `<tr><td>${esc(line.label)}</td>${cells}</tr>`;
    })
    .join("");
  return `<section class="wide"><h2>${esc(title)}</h2><table><thead><tr><th></th>${head}</tr></thead><tbody>${body}</tbody></table>${note ? `<p class="note">${note}</p>` : ""}</section>`;
}

const ratio = (a: number, b: number) => (b ? (100 * a) / b : 0);

/** A ranked list of a few rows. */
function list(title: string, rows: { label: string; values: number[] }[], columns: string[]): string {
  if (!rows.length) return `<section><h2>${esc(title)}</h2><p class="muted">No data yet.</p></section>`;
  return `<section><h2>${esc(title)}</h2><table><thead><tr><th></th>${columns.map((c) => `<th>${esc(c)}</th>`).join("")}</tr></thead><tbody>${rows
    .map((r) => `<tr><td>${esc(r.label || "(not set)")}</td>${r.values.map((v) => `<td class="n">${num(v)}</td>`).join("")}</tr>`)
    .join("")}</tbody></table></section>`;
}

/** The daily report's sections, as HTML. */
export async function dailyReport(env: AdminEnv, fetcher: typeof fetch = fetch, now = new Date()): Promise<string> {
  const dates = windowDates(now);
  const [web, clicks, app, store] = [
    reports(dates, WEB, ["totalUsers", "newUsers", "sessions", "screenPageViews"]),
    reports(dates, CLICKS, ["eventCount", "totalUsers"]),
    reports(dates, APP, ["activeUsers", "newUsers", "sessions", "userEngagementDuration"]),
    reports(dates, STORE, ["activeUsers", "newUsers", "sessions", "userEngagementDuration"]),
  ];
  const sources: Report = {
    dateRanges: [{ startDate: dates.week.now.start, endDate: dates.week.now.end }],
    dimensions: [{ name: "firstUserSourceMedium" }],
    metrics: [{ name: "newUsers" }],
    orderBys: [{ metric: { metricName: "newUsers" }, desc: true }],
    limit: 8,
    dimensionFilter: WEB,
  };
  const search = (body: object) => googlePost(env, SEARCH, body, fetcher).then((r) => ((r as { rows?: SearchRow[] }).rows ?? []) as SearchRow[]);
  const [ga, storeA, storeB, byDate, queries, pages] = await Promise.all([
    batch(env, [web[0], web[1], clicks[0], clicks[1], sources], fetcher),
    // The build is a custom dimension: Google refuses it until it has data, so apart.
    single(env, store[0], fetcher),
    single(env, store[1], fetcher),
    search({ startDate: dates.month.before.start, endDate: dates.day.now.end, dimensions: ["date"], rowLimit: 100 }).catch(() => null),
    search({ startDate: dates.week.now.start, endDate: dates.week.now.end, dimensions: ["query"], rowLimit: 10 }).catch(() => null),
    search({ startDate: dates.week.now.start, endDate: dates.week.now.end, dimensions: ["page"], rowLimit: 10 }).catch(() => null),
  ]);
  const [appA, appB] = await batch(env, [app[0], app[1]], fetcher);
  const clickB = block(ga[2], ga[3], 2);
  // The website's four numbers and its App Store clicks (times) as a fifth.
  const webOnly = block(ga[0], ga[1], 4);
  const webB = Object.fromEntries(WINDOWS.map((w) => [w.id, [...webOnly[w.id], clickB[w.id][0]]])) as Block;
  const appAll = block(appA, appB, 4);
  const storeB2 = storeA || storeB ? block(storeA, storeB, 4) : null;
  const searchB = byDate ? searchBlock(byDate, dates) : null;

  // The funnel: visitors → App Store clicks → (Apple: page views, downloads) → new App Store users.
  const funnel: Block = Object.fromEntries(
    WINDOWS.map((w) => [w.id, [webB[w.id][0], clickB[w.id][1], storeB2 ? storeB2[w.id][1] : { now: 0, before: 0 }]]),
  ) as Block;

  const appLines = (label: string): Line[] => [
    { label: `Active ${label} (people)`, value: 0 },
    { label: "New users (first opens)", value: 1 },
    { label: "Sessions", value: 2 },
    { label: "Sessions per active user", value: (m, s) => (m[0][s] ? m[2][s] / m[0][s] : 0), digits: 1 },
    { label: "Minutes per active user", value: (m, s) => (m[0][s] ? m[3][s] / m[0][s] / 60 : 0), digits: 1 },
  ];

  return `<p class="note">Days end yesterday, ${dates.day.now.end}, Kyiv time. Google Analytics counts website visitors who accepted cookies; Search Console is 2–3 days late and counts in Pacific time.</p>
<div class="stack">
${table("Funnel: Google and the website to the app", funnel, [
    { label: "Website visitors (people)", value: 0 },
    { label: "Clicked App Store (people)", value: 1 },
    { label: "Clicked, % of visitors", value: (m, s) => ratio(m[1][s], m[0][s]), digits: 1 },
    { label: "New App Store users (first opens)", value: 2 },
  ], "App Store page views and downloads per website button come from App Store Connect's Campaigns once its key is added; Apple shows a campaign from 5 downloads, a day or two late, and never who.")}
${table("Google Search", searchB, [
    { label: "Clicks to the site", value: 0 },
    { label: "Impressions in results", value: 1 },
    { label: "Click rate, %", value: 2, digits: 1 },
    { label: "Average position", value: 3, digits: 1, lowerIsBetter: true },
  ], searchB ? "" : "Search Console did not answer.")}
${table("Website", webB, [
    { label: "Visitors (people)", value: 0 },
    { label: "New visitors (people)", value: 1 },
    { label: "Sessions", value: 2 },
    { label: "Page views", value: 3 },
    { label: "App Store clicks (times)", value: 4 },
  ])}
${table("App: App Store build", storeB2, appLines("users"), storeB2 ? "Only readers of the App Store build (build = store): the release." : "No App Store build in use yet: it counts from the release.")}
${table("App: every build (TestFlight included)", appAll, appLines("users"))}
</div>
<div class="grid" style="margin-top:12px">
${list("Google searches, last 7 days", (queries ?? []).map((r) => ({ label: r.keys![0], values: [r.clicks, r.impressions] })), ["Clicks", "Impressions"])}
${list("Pages from Google, last 7 days", (pages ?? []).map((r) => ({ label: r.keys![0].replace(/^https:\/\/outernews\.app/, ""), values: [r.clicks, r.impressions] })), ["Clicks", "Impressions"])}
${list("Where new visitors came from, last 7 days", ga[4].rows.map((r) => ({ label: r.key[0], values: r.values })), ["New visitors"])}
</div>`;
}

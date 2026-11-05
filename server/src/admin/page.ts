// The admin page's HTML (#60, Yurii 28 Oct): one place for analytics, by
// tab: the daily report (#60, 3 Nov), the website, the app, downloads once the
// app is in the store, and readers' messages (#220).
// Server-rendered, no script; the numbers come from Google Analytics (ga.ts).
import type { CloudflareDay } from "./cloudflare";
import type { Rows } from "./ga";

export type Tab = "daily" | "website" | "app" | "downloads" | "messages";
export const TABS: { id: Tab; label: string }[] = [
  { id: "daily", label: "Daily" },
  { id: "website", label: "Website" },
  { id: "app", label: "App" },
  { id: "downloads", label: "Downloads" },
  { id: "messages", label: "Messages" },
];
export const PERIODS = [7, 28, 90] as const;

export const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const num = (n: number) => Math.round(n).toLocaleString("en-US");
const duration = (seconds: number) => (seconds >= 60 ? `${Math.floor(seconds / 60)}m ${Math.round(seconds % 60)}s` : `${Math.round(seconds)}s`);

/** "+12%" against the period before; nothing when there was nothing before. */
function change(now: number, before: number) {
  if (!before) return "";
  const pct = Math.round(((now - before) / before) * 100);
  return `<span class="${pct >= 0 ? "up" : "down"}">${pct >= 0 ? "+" : ""}${pct}%</span>`;
}

/**
 * The headline numbers: users, new users, sessions, views and engagement per
 * user, against the period before; returning users from Google's own
 * new/returning split (`newVs` for this period), since users less new users
 * is not it (a user first seen in the period can come back in it too).
 */
export function totals(report: Rows, viewsLabel: string, newVs?: Rows): string {
  const pick = (name: string) => report.rows.find((r) => r.key[0] === name)?.values ?? [0, 0, 0, 0, 0];
  const now = pick("now");
  const before = pick("before");
  const perUser = (v: number[]) => (v[0] ? v[4] / v[0] : 0);
  const cards: [string, string, string][] = [
    ["Users", num(now[0]), change(now[0], before[0])],
    ["New users", num(now[1]), change(now[1], before[1])],
    ["Returning users", num(newVs?.rows.find((r) => r.key[0] === "returning")?.values[0] ?? 0), ""],
    ["Sessions", num(now[2]), change(now[2], before[2])],
    [viewsLabel, num(now[3]), change(now[3], before[3])],
    ["Time per user", duration(perUser(now)), change(perUser(now), perUser(before))],
  ];
  return `<div class="cards">${cards.map(([label, value, delta]) => `<div class="card"><p>${label}</p><b>${value}</b>${delta}</div>`).join("")}</div>`;
}

/** A ranked table: the label column, then each metric; "No data yet" when empty. */
export function table(title: string, report: Rows | null, columns: string[], label: (key: string[]) => string = (k) => k.join(" · ")): string {
  if (!report) return `<section><h2>${esc(title)}</h2><p class="muted">Not available yet: it counts from the day it was set up.</p></section>`;
  if (!report.rows.length) return `<section><h2>${esc(title)}</h2><p class="muted">No data yet.</p></section>`;
  const head = columns.map((c) => `<th>${esc(c)}</th>`).join("");
  const body = report.rows
    .map((r) => `<tr><td>${esc(label(r.key) || "(not set)")}</td>${r.values.map((v) => `<td class="n">${num(v)}</td>`).join("")}</tr>`)
    .join("");
  return `<section><h2>${esc(title)}</h2><table><thead><tr><th></th>${head}</tr></thead><tbody>${body}</tbody></table></section>`;
}

/**
 * The period day by day, today first (Yurii, 5 Nov): new and returning
 * visitors and their sessions from Google Analytics (those who accepted
 * cookies, Google's own new/returning split, in the property's time zone),
 * and every visit from Cloudflare (no cookies, UTC days). `perDay` has rows
 * keyed [YYYYMMDD, "new" | "returning" | "(not set)"] with [users, sessions].
 */
export function dayTable(dates: string[], perDay: Rows | null, cloudflare: Map<string, CloudflareDay> | null): string {
  const day = new Map<string, { fresh: number; back: number; sessions: number }>();
  for (const r of perDay?.rows ?? []) {
    const d = r.key[0] ?? "";
    const date = `${d.slice(0, 4)}-${d.slice(4, 6)}-${d.slice(6, 8)}`;
    const row = day.get(date) ?? { fresh: 0, back: 0, sessions: 0 };
    if (r.key[1] === "new") row.fresh += r.values[0] ?? 0;
    if (r.key[1] === "returning") row.back += r.values[0] ?? 0;
    row.sessions += r.values[1] ?? 0;
    day.set(date, row);
  }
  const label = (date: string) => new Date(`${date}T12:00:00Z`).toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short", timeZone: "UTC" });
  const cf = (date: string) => (cloudflare ? num(cloudflare.get(date)?.visits ?? 0) : "–");
  const body = dates
    .map((date) => {
      const row = day.get(date) ?? { fresh: 0, back: 0, sessions: 0 };
      return `<tr><td>${esc(label(date))}</td><td class="n">${num(row.fresh)}</td><td class="n">${num(row.back)}</td><td class="n">${num(row.sessions)}</td><td class="n">${cf(date)}</td></tr>`;
    })
    .join("");
  return `<section><h2>Day by day</h2><table><thead><tr><th></th><th>New visitors</th><th>Returning visitors</th><th>Sessions</th><th>Visits, everyone (Cloudflare)</th></tr></thead><tbody>${body}</tbody></table>
<p class="note">New, returning and sessions: Google Analytics, visitors who accepted cookies. Visits, everyone: Cloudflare, no cookies, UTC days${cloudflare ? "" : " (not available right now)"}.</p></section>`;
}

const EVENT_NAMES: Record<string, string> = {
  open_article: "Articles opened",
  article_read: "Articles read (attention)",
  open_official_link: "Official links opened",
  share: "Shares",
  screen_view: "Screens viewed",
  filter_changed: "Filters changed",
  select_language: "Language changed",
  discuss_ai_tap: "Discuss with AI tapped",
  paywall_view: "Paywall shown",
  subscribe_result: "Subscription results",
  chat_question: "Chat questions",
  push_open: "Pushes opened",
  feed_load_failed: "Feed failed to load",
  first_open: "First opens",
  session_start: "Sessions started",
  user_engagement: "Engagement pings",
};

/** An event's name in words: "Design chosen: garnet", "Scrolled 20 rows"; else the raw name. */
export function eventLabel(name: string): string {
  if (EVENT_NAMES[name]) return EVENT_NAMES[name];
  const design = /^design_(.+)$/.exec(name);
  if (design) return `Design chosen: ${design[1]}`;
  const scroll = /^feed_scroll_(\d+)$/.exec(name);
  if (scroll) return `Scrolled ${scroll[1]} rows`;
  return name;
}

/** The whole page: the tabs, the period, then the tab's sections (already HTML). */
export function page(tab: Tab, days: number, email: string, sections: string): string {
  const tabs = TABS.map((t) => `<a href="?tab=${t.id}&amp;days=${days}"${t.id === tab ? ' aria-current="page"' : ""}>${t.label}</a>`).join("");
  const periods = PERIODS.map((d) => `<a href="?tab=${tab}&amp;days=${d}"${d === days ? ' aria-current="page"' : ""}>${d} days</a>`).join("");
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex, nofollow">
<title>Admin · Outer News</title>
<style>
:root{color-scheme:light dark;--bg:#f2f2f7;--card:#fff;--text:#000;--muted:#6c6c70;--line:#e5e5ea;--accent:#c41230;--up:#1a7f37;--down:#c41230}
@media (prefers-color-scheme:dark){:root{--bg:#000;--card:#1c1c1e;--text:#fff;--muted:#98989f;--line:#38383a;--accent:#ff5a72;--up:#3fb950;--down:#ff5a72}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
.wrap{max-width:1100px;margin:0 auto;padding:20px 16px 48px}header{display:flex;justify-content:space-between;align-items:baseline;gap:12px;flex-wrap:wrap}
h1{margin:0;font:700 28px/1.2 Georgia,"Times New Roman",serif}.who{color:var(--muted);font-size:13px}
nav{display:flex;gap:6px;flex-wrap:wrap;margin:16px 0 0}nav a{padding:8px 14px;border-radius:18px;color:var(--text);text-decoration:none;background:var(--card);font-weight:600}nav a[aria-current]{background:var(--accent);color:#fff}
nav.periods a{padding:5px 11px;font-size:13px;font-weight:500}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin:20px 0}.card{background:var(--card);border-radius:14px;padding:14px}
.card p{margin:0;color:var(--muted);font-size:13px}.card b{display:block;font-size:26px;margin:2px 0}.up{color:var(--up);font-size:13px}.down{color:var(--down);font-size:13px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:12px}section{background:var(--card);border-radius:14px;padding:14px 16px}
h2{margin:0 0 8px;font:700 17px/1.3 Georgia,"Times New Roman",serif}table{width:100%;border-collapse:collapse;font-size:14px}th{color:var(--muted);font-weight:500;text-align:right;padding:4px 0 6px 8px}th:first-child{text-align:left}
td{padding:6px 0;border-top:.5px solid var(--line);overflow-wrap:anywhere}td.n{text-align:right;padding-left:8px;font-variant-numeric:tabular-nums}.muted{color:var(--muted)}.note{margin:16px 0 0;color:var(--muted);font-size:13px}
.stack{display:grid;gap:12px;margin-top:12px}section.wide{overflow-x:auto}section.wide table{min-width:620px}
.thread{margin-top:12px}.msg{margin:8px 0;padding:8px 12px;border-radius:12px;background:var(--bg)}.msg.team{margin-left:24px}.msg p{margin:0;white-space:pre-wrap;overflow-wrap:anywhere}.msg small{color:var(--muted)}
.thread form{display:inline-block;margin:8px 8px 0 0}.thread form.reply{display:block}.thread textarea{width:100%;font:15px/1.4 -apple-system,sans-serif;background:var(--bg);color:var(--text);border:.5px solid var(--line);border-radius:10px;padding:8px}
.thread button{min-height:36px;padding:0 16px;border:0;border-radius:18px;background:var(--accent);color:#fff;font:600 14px -apple-system,sans-serif;cursor:pointer;margin-top:6px}.thread button.plain{background:var(--line);color:var(--text)}
</style></head>
<body><div class="wrap">
<header><h1>Outer News · Admin</h1><span class="who">${esc(email)}</span></header>
<nav aria-label="Tabs">${tabs}</nav>
${tab === "messages" || tab === "daily" ? "" : `<nav class="periods" aria-label="Period">${periods}</nav>`}
${sections}
</div></body></html>`;
}

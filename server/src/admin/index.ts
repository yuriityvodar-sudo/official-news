// The admin page (#60, Yurii 28 Oct): admin.outernews.app, behind Cloudflare
// Access (only Yurii and Roman), with the analytics of the website and the
// app from Google Analytics, by tab. Its own Worker, so the public website
// keeps holding no key at all (docs/decisions.md).
import { signedInEmail } from "./access";
import type { AdminEnv } from "./env";
import { KEY_NAME, type Request as Report, account, batch, forgetToken, single } from "./ga";
import { messagePost, messagesTab } from "./messages";
import { makeSelfKey, type SelfKey } from "./selfkey";
import { PERIODS, type Tab, TABS, eventLabel, page, table, totals } from "./page";

const HEADERS = {
  "content-type": "text/html; charset=utf-8",
  "cache-control": "private, no-store",
  "x-robots-tag": "noindex, nofollow",
  "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'",
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
};

const WEB = { filter: { fieldName: "platform", stringFilter: { value: "web" } } };
const APP = { filter: { fieldName: "platform", inListFilter: { values: ["iOS", "Android"] } } };
const TOTALS = ["totalUsers", "newUsers", "sessions", "screenPageViews", "userEngagementDuration"].map((name) => ({ name }));

const ranges = (days: number) => [
  { startDate: `${days - 1}daysAgo`, endDate: "today", name: "now" },
  { startDate: `${2 * days - 1}daysAgo`, endDate: `${days}daysAgo`, name: "before" },
];
const totalsReport = (days: number, filter: object): Report => ({ dateRanges: ranges(days), metrics: TOTALS, dimensionFilter: filter });
const top = (days: number, filter: object, dimension: string, metrics: string[], limit = 10): Report => ({
  dateRanges: [ranges(days)[0]],
  dimensions: [{ name: dimension }],
  metrics: metrics.map((name) => ({ name })),
  orderBys: [{ metric: { metricName: metrics[0] }, desc: true }],
  limit,
  dimensionFilter: filter,
});

async function website(env: AdminEnv, days: number, fetcher: typeof fetch): Promise<string> {
  const [t, sources, pages, countries, returning] = await batch(
    env,
    [
      totalsReport(days, WEB),
      top(days, WEB, "sessionSourceMedium", ["sessions", "totalUsers"]),
      top(days, WEB, "pagePath", ["screenPageViews", "totalUsers"], 15),
      top(days, WEB, "country", ["totalUsers"]),
      top(days, WEB, "newVsReturning", ["totalUsers", "sessions"]),
    ],
    fetcher,
  );
  return `${totals(t, "Page views", returning)}
<div class="grid">
${table("Where visitors come from", sources, ["Sessions", "Users"])}
${table("Most read pages", pages, ["Views", "Users"])}
${table("Countries", countries, ["Users"])}
${table("New and returning", returning, ["Users", "Sessions"])}
</div>
<p class="note">Counts visitors who allowed analytics on the site's banner. Google searches and clicks (Search Console) come once the site is open to Google.</p>`;
}

async function app(env: AdminEnv, days: number, fetcher: typeof fetch): Promise<string> {
  const [core, design, home, language, build] = await Promise.all([
    batch(
      env,
      [
        totalsReport(days, APP),
        top(days, APP, "eventName", ["eventCount", "totalUsers"], 25),
        top(days, APP, "country", ["totalUsers"]),
        top(days, APP, "newVsReturning", ["totalUsers", "sessions"]),
        top(days, APP, "unifiedScreenName", ["screenPageViews", "userEngagementDuration"]),
      ],
      fetcher,
    ),
    single(env, top(days, APP, "customUser:feed_design", ["totalUsers"]), fetcher),
    single(env, top(days, APP, "customUser:home_country", ["totalUsers"]), fetcher),
    single(env, top(days, APP, "customUser:feed_language", ["totalUsers"]), fetcher),
    single(env, top(days, APP, "customUser:build", ["totalUsers"]), fetcher),
  ]);
  const [t, events, countries, returning, screens] = core;
  return `${totals(t, "Screens viewed", returning)}
<div class="grid">
${table("What people do", events, ["Times", "Users"], (k) => eventLabel(k[0]))}
${table("Screens (views, seconds spent)", screens, ["Views", "Seconds"])}
${table("Design in use", design, ["Users"])}
${table("Reading language", language, ["Users"])}
${table("Home country (For you)", home, ["Users"])}
${table("Countries", countries, ["Users"])}
${table("New and returning", returning, ["Users", "Sessions"])}
${table("Build (testflight = the team)", build, ["Users"])}
</div>`;
}

const downloads = () =>
  `<section style="margin-top:20px"><h2>Downloads</h2><p class="muted">Downloads and store page views come from App Store Connect once the app is released. They need an App Store Connect key with the Sales role, added as a Worker secret like the Google one.</p></section>`;

const message = (status: number, title: string, text: string) =>
  new Response(`<!doctype html><meta charset="utf-8"><meta name="robots" content="noindex"><title>${title}</title><body style="font:16px -apple-system,sans-serif;padding:40px;max-width:560px"><h1 style="font-family:Georgia,serif">${title}</h1><p>${text}</p></body>`, { status, headers: HEADERS });

const connectSection = () => `<section style="margin-top:20px"><h2>Connect Google Analytics</h2>
<p class="muted">One click: this page makes its own Google key. The private part stays inside Cloudflare and is never shown; only a public certificate is shown, to upload to Google once.</p>
<form method="post" action="/connect"><button type="submit" style="min-height:44px;padding:0 20px;border:0;border-radius:22px;background:var(--accent);color:#fff;font:600 15px -apple-system,sans-serif;cursor:pointer">Connect Google Analytics</button></form></section>`;

const certificateSection = (key: SelfKey, clientEmail: string, why: string) => `<section style="margin-top:20px"><h2>One step left: upload this certificate to Google</h2>
<p class="muted">In Google Cloud, service account <b>${clientEmail}</b> → Keys → Add key → Upload existing key, paste this, and Upload. It is the public half only: safe to copy. (Google said: ${why})</p>
<textarea readonly rows="12" style="width:100%;font:12px ui-monospace,Menlo,monospace;background:var(--bg);color:var(--text);border:.5px solid var(--line);border-radius:10px;padding:10px">${key.certificatePem}</textarea></section>`;

/**
 * POST /connect: makes the page's own Google key once (selfkey.ts) and goes
 * back to the page, which then shows the certificate to upload. Only from
 * this page itself (its Origin), and never over a key that exists.
 */
async function connect(env: AdminEnv): Promise<Response> {
  if (!(await env.ADMIN_KV.get(KEY_NAME))) {
    await env.ADMIN_KV.put(KEY_NAME, JSON.stringify(await makeSelfKey("Outer News admin")));
    forgetToken();
  }
  return new Response(null, { status: 303, headers: { location: "/?tab=website", "cache-control": "no-store" } });
}

/**
 * Whether a POST comes from this page itself. The browser says where a click
 * came from: Sec-Fetch-Site, or Origin (which it sends as "null" under the
 * page's no-referrer policy, so not alone).
 */
function fromThisPage(request: Request): boolean {
  return request.headers.get("sec-fetch-site") === "same-origin" || request.headers.get("origin") === new URL(request.url).origin;
}

const POSTS = ["/connect", "/messages/reply", "/messages/close"];

export async function handleAdmin(request: Request, env: AdminEnv, fetcher: typeof fetch = fetch): Promise<Response> {
  const url = new URL(request.url);
  const post = request.method === "POST" && POSTS.includes(url.pathname);
  if (request.method !== "GET" && request.method !== "HEAD" && !post) return message(405, "Not allowed", `Only GET, and POST ${POSTS.join(", ")}.`);
  const email = await signedInEmail(request, env, fetcher).catch(() => null);
  if (!email) return message(403, "Not signed in", "This page is for the Outer News team. Sign in through Cloudflare Access at admin.outernews.app.");
  if (post) {
    if (!fromThisPage(request)) return message(403, "Not allowed", "Only from the admin page.");
    if (url.pathname === "/connect") return connect(env);
    // Readers' messages (#220): a reply or Close, then back to the tab.
    const form = await request.formData().catch(() => new FormData());
    const error = await messagePost(url.pathname, form, env);
    if (error) return message(400, "Not sent", error);
    return new Response(null, { status: 303, headers: { location: "/?tab=messages", "cache-control": "no-store" } });
  }
  const tab: Tab = TABS.some((t) => t.id === url.searchParams.get("tab")) ? (url.searchParams.get("tab") as Tab) : "website";
  const asked = Number(url.searchParams.get("days"));
  const days = (PERIODS as readonly number[]).includes(asked) ? asked : 28;
  if (tab === "messages") return new Response(request.method === "HEAD" ? null : page(tab, days, email, await messagesTab(env)), { headers: HEADERS });
  if (tab !== "downloads" && !(await account(env))) {
    return new Response(page(tab, days, email, connectSection()), { headers: HEADERS });
  }
  let sections: string;
  try {
    sections = tab === "website" ? await website(env, days, fetcher) : tab === "app" ? await app(env, days, fetcher) : downloads();
  } catch (error) {
    // The reason only (Google's message or a missing field), never a key.
    const why = String(error instanceof Error ? error.message : error).replace(/[<>&]/g, "");
    const key = await env.ADMIN_KV.get<SelfKey>(KEY_NAME, "json");
    // A self-made key Google does not know yet: show the certificate to upload.
    sections = key && !env.GA_SERVICE_ACCOUNT && /sign-in|invalid_grant|JWT|signature/i.test(why)
      ? certificateSection(key, env.GA_CLIENT_EMAIL, why)
      : `<section style="margin-top:20px"><h2>Google Analytics did not answer</h2><p class="muted">${why}</p></section>`;
  }
  return new Response(request.method === "HEAD" ? null : page(tab, days, email, sections), { headers: HEADERS });
}

export default { fetch: (request: Request, env: AdminEnv) => handleAdmin(request, env) } satisfies ExportedHandler<AdminEnv>;

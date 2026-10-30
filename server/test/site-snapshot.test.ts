// The website's snapshot of the feed (#88, 30 Oct): one D1 row per language,
// built by the api Worker's cron (api/snapshot.ts) and read by every list page
// in place of the API's queries (site/data.ts, site/snapshot.ts). What it
// answers must be what the API answers, page by page, for every filter and
// language; without a fresh row the site reads the API as before.
import { createScheduledController } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it, vi } from "vitest";
import worker, { CRONS } from "../src/index";
import { SNAPSHOT_EVERY_MINUTES, SNAPSHOT_FULL_MS, SNAPSHOT_LANGS, SNAPSHOT_MAX_AGE_MS, type Snapshot, type SnapshotArticle, type TopCandidate, snapshotLang, snapshotStep } from "../src/api/snapshot";
import { GROUPS } from "../src/api/filters";
import { type ApiList, listData } from "../src/site/data";
import { snapshotTop } from "../src/site/snapshot";
import { SITE_LANGS, type SiteLang } from "../src/site/texts";
import type { ListFilter } from "../src/site/urls";
import { get, hideSeed, testEnv } from "./helpers";
import { insertArticle, insertTranslation, refreshSite, site, siteEnv, siteRowsRead as rowsRead, testId } from "./site-helpers";

const SOURCE = { DE: "de-federal-government", EU: "eu-european-commission", FR: "fr-foreign-ministry", US: "us-white-house", GB: "gb-prime-minister-s-office" } as const;

/** 50 articles over 3 pages: Germany, the EU institutions and the US in turn, on two topics, with Ukrainian and Spanish translations of some; and one of France and the UK each. */
async function fixtures() {
  await hideSeed();
  await env.DB.prepare(`UPDATE sources SET config = NULL WHERE id IN (${Object.values(SOURCE).map(() => "?").join(", ")})`)
    .bind(...Object.values(SOURCE))
    .run();
  const countries = ["DE", "EU", "US"] as const;
  for (let n = 10; n < 58; n++) {
    await insertArticle({
      id: testId(n),
      sourceId: SOURCE[countries[n % 3]],
      topics: [n % 2 ? "health" : "economy"],
      importance: n % 6 === 0 ? null : n % 5,
      // Some older than the top stories' 72 hours, one older than the feed's 7 days (never shown).
      publishedAt: n % 7 === 0 ? `${new Date(Date.now() - 80 * 3_600_000).toISOString().slice(0, 19)}Z` : n === 57 ? "2026-01-01T10:00:00Z" : undefined,
    });
    if (n % 4 === 0) await insertTranslation(testId(n), "uk");
    if (n % 3 === 0) await insertTranslation(testId(n), "es");
  }
  await insertArticle({ id: testId(60), sourceId: SOURCE.FR, topics: ["climate"], importance: 5 });
  await insertArticle({ id: testId(61), sourceId: SOURCE.GB, topics: ["security-defence"] });
  await insertTranslation(testId(61), "uk");
}

beforeEach(fixtures);

const atMinute = (minute: number) => Date.UTC(2026, 9, 30, 12, minute);

const snapshotRows = async () =>
  (await env.DB.prepare("SELECT lang, updated_at FROM site_snapshots ORDER BY lang").all<{ lang: string; updated_at: string }>()).results;

const ids = (list: { items: { id: string }[]; top: { id: string }[] }) => ({ items: list.items.map((a) => a.id), top: list.top.map((a) => a.id) });

/** The API's query for a site list's filter. */
function apiQuery(lang: SiteLang, filter: ListFilter): string {
  const params = new URLSearchParams({ limit: "20" });
  if (lang !== "en") params.set("lang", lang);
  if (filter.place && "country" in filter.place) params.set("country", filter.place.country);
  if (filter.place && "group" in filter.place) params.set("group", filter.place.group);
  if (filter.topic) params.set("topic", filter.topic);
  return `/articles?${params}`;
}

const FILTERS: ListFilter[] = [
  { place: null, topic: null },
  { place: { country: "DE" }, topic: null },
  { place: { country: "US" }, topic: "health" },
  { place: { country: "FR" }, topic: null },
  { place: { country: "UA" }, topic: null },
  ...GROUPS.map((g) => ({ place: { group: g.id }, topic: null })),
  { place: { group: "g7" }, topic: "economy" },
  { place: null, topic: "health" },
  { place: null, topic: "science" },
];

describe("the cron step", () => {
  it("covers the site's languages, one a run by the minute, so each is rebuilt every 5 minutes", () => {
    expect(SNAPSHOT_LANGS).toEqual(SITE_LANGS);
    expect(SNAPSHOT_EVERY_MINUTES).toBe(5);
    expect([0, 1, 2, 3, 4, 5, 59, 60].map((m) => snapshotLang(atMinute(m)))).toEqual(["en", "uk", "ru", "es", "de", "en", "de", "en"]);
    expect(SNAPSHOT_FULL_MS).toBeGreaterThan(2 * SNAPSHOT_EVERY_MINUTES * 60_000);
    // A run that fails is tried again 5 minutes later, twice, before the row goes stale.
    expect(SNAPSHOT_MAX_AGE_MS - SNAPSHOT_FULL_MS).toBeGreaterThanOrEqual(2 * SNAPSHOT_EVERY_MINUTES * 60_000);
  });

  it("rebuilds a language when its feed changed, or once its row is 20 minutes old, and otherwise reads 3 rows and leaves it", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    const at = (minutes: number) => new Date(Date.UTC(2026, 9, 30, 12, minutes));
    const row = () => env.DB.prepare("SELECT version, updated_at FROM site_snapshots WHERE lang = 'uk'").first<{ version: string; updated_at: string }>();
    await snapshotStep(env, atMinute(1), at(1));
    const first = await row();
    expect(first?.updated_at).toBe("2026-10-30T12:01:00Z");
    // Nothing changed: left as it is.
    expect(await rowsRead(() => snapshotStep(env, atMinute(6), at(6)))).toBeLessThanOrEqual(3);
    expect(await row()).toEqual(first);
    // A new translation into the language: rebuilt.
    await insertTranslation(testId(11), "uk");
    await snapshotStep(env, atMinute(11), at(11));
    expect((await row())?.updated_at).toBe("2026-10-30T12:11:00Z");
    expect((await row())?.version).not.toBe(first?.version);
    // A release (any language's feed): rebuilt.
    await insertArticle({ id: testId(70) });
    await snapshotStep(env, atMinute(16), at(16));
    expect((await row())?.updated_at).toBe("2026-10-30T12:16:00Z");
    // A summary of an article not released yet, or another language's translation, changes nothing on the site: left.
    await insertArticle({ id: testId(71), released: false });
    await insertTranslation(testId(13), "es");
    await snapshotStep(env, atMinute(21), at(21));
    expect((await row())?.updated_at).toBe("2026-10-30T12:16:00Z");
    // 20 minutes without a change: rebuilt anyway.
    await snapshotStep(env, atMinute(36), at(36));
    expect((await row())?.updated_at).toBe("2026-10-30T12:36:00Z");
  });

  it("writes the language's row at the end of the translator's and the summarizer's runs", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    const keyless = { ...testEnv(null, undefined, null), FCM_SERVICE_ACCOUNT: undefined };
    await worker.scheduled(createScheduledController({ cron: CRONS.translator, scheduledTime: atMinute(10) }), keyless);
    expect((await snapshotRows()).map((r) => r.lang)).toEqual(["en"]);
    await worker.scheduled(createScheduledController({ cron: CRONS.summarizer, scheduledTime: atMinute(11) }), keyless);
    expect((await snapshotRows()).map((r) => r.lang)).toEqual(["en", "uk"]);
    // A second run of the same language has one row to keep or replace, never a second one.
    await insertArticle({ id: testId(70) });
    await worker.scheduled(createScheduledController({ cron: CRONS.translator, scheduledTime: atMinute(20) }), keyless);
    expect((await snapshotRows()).map((r) => r.lang)).toEqual(["en", "uk"]);
    // The row is what the pages read: a list page is then one row.
    expect(await rowsRead(() => site("/en"))).toBe(1);
    expect(await rowsRead(() => site("/uk/de?topic=health"))).toBe(1);
  });

  it("reads a bounded number of rows for a round of the 5 languages, and keeps the JSON small", async () => {
    const rows = await rowsRead(() => refreshSite());
    const sizes = (await env.DB.prepare("SELECT lang, length(json) AS bytes FROM site_snapshots ORDER BY lang").all<{ lang: string; bytes: number }>()).results;
    expect(sizes.map((s) => s.lang)).toEqual(["de", "en", "es", "ru", "uk"]);
    for (const { lang, bytes } of sizes) expect(bytes, lang).toBeLessThan(500_000);
    // The numbers, for docs/decisions.md (a test database of 50 articles; live, about 300 in the feed).
    console.log(JSON.stringify({ rowsRead: { snapshotRound: rows }, bytes: Object.fromEntries(sizes.map((s) => [s.lang, s.bytes])) }));
    expect(rows).toBeLessThan(1_000);
  });
});

describe("a list page from the snapshot", () => {
  beforeEach(() => refreshSite());

  it("is the API's page, page by page: items, top stories and the next page, for every filter in every language", async () => {
    let multiPage = 0;
    for (const lang of SITE_LANGS) {
      for (const filter of FILTERS) {
        const name = `${lang} ${JSON.stringify(filter)}`;
        let before: number | null = null;
        let cursor: string | null = null;
        do {
          const ours = await listData(siteEnv(), lang, { filter, before });
          const api = (await get(`${apiQuery(lang, filter)}${cursor ? `&cursor=${cursor}` : ""}`)).body as ApiList;
          expect(ids(ours.list), `${name} before=${before}`).toEqual(ids(api));
          expect(ours.list.nextCursor, `${name} before=${before}`).toBe(api.nextCursor);
          // The page's texts are the API's too: the headline, the summary and the source's name in the language.
          expect(ours.list.items.map((a) => [a.headline, a.shortSummary, a.source.name, a.countries, a.topics, a.dateOnly, a.feedSeq, a.addedAt]), name).toEqual(
            api.items.map((a) => [a.headline, a.shortSummary, a.source.name, a.countries, a.topics, a.dateOnly, a.feedSeq, a.addedAt]),
          );
          cursor = api.nextCursor;
          before = ours.list.items.at(-1)?.feedSeq ?? null;
          if (before !== null && cursor) multiPage++;
        } while (cursor);
      }
    }
    // The unfiltered English list has 3 pages, the groups 2 or 3: paging is exercised.
    expect(multiPage).toBeGreaterThanOrEqual(6);
  });

  it("offers the menus the API offers: GET /countries, and GET /topics for the place in the language", async () => {
    for (const lang of SITE_LANGS) {
      for (const filter of FILTERS) {
        const { menus } = await listData(siteEnv(), lang, { filter, before: null });
        const query = apiQuery(lang, filter).replace("/articles?limit=20", "").replace(/&?topic=[a-z-]+/, "").replace(/^&/, "?");
        expect(menus?.where, `${lang} ${JSON.stringify(filter)}`).toEqual((await get(`/countries${lang === "en" ? "" : `?lang=${lang}`}`)).body);
        expect(menus?.topics, `${lang} ${JSON.stringify(filter)}`).toEqual(((await get(`/topics${query}`)).body as { topics: unknown }).topics);
      }
      expect((await listData(siteEnv(), lang, { filter: { place: null, topic: null }, before: 30 })).menus).toBeNull();
    }
  });

  it("renders the same HTML as the API's queries do, and the same sitemap", async () => {
    const paths = ["/en", "/en/de", "/en/g7?topic=economy", "/uk", "/uk/eu", "/es?topic=health", "/de", "/en/fr", "/sitemap-latest.xml"];
    const fromSnapshot = await Promise.all(paths.map((p) => site(p)));
    const next = /<a class="more" href="([^"]+)" rel="next nofollow">/.exec(fromSnapshot[0].body)![1];
    const laterFromSnapshot = await site(next);
    await env.DB.prepare("DELETE FROM site_snapshots").run();
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const fromApi = await Promise.all(paths.map((p) => site(p)));
    for (const [i, path] of paths.entries()) {
      expect(fromSnapshot[i].status, path).toBe(200);
      expect(fromSnapshot[i].body, path).toBe(fromApi[i].body);
    }
    expect(laterFromSnapshot.body).toBe((await site(next)).body);
  });

  it("falls back to the API's queries when the snapshot is missing or older than 30 minutes, and says so in the log", async () => {
    expect(await rowsRead(() => site("/en/g7"))).toBe(1);
    // rowsRead restores every spy when it is done, so the log is watched between its calls.
    let warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    await site("/en/g7");
    expect(warn).not.toHaveBeenCalled();

    await refreshSite(new Date(Date.now() - SNAPSHOT_MAX_AGE_MS - 60_000));
    const stale = await site("/en/g7");
    expect(stale.status).toBe(200);
    expect(stale.body).toContain('class="title"');
    expect(JSON.parse(String(warn.mock.calls.at(-1)?.[0]))).toMatchObject({ message: "site snapshot stale", lang: "en" });
    expect(await rowsRead(() => site("/en/g7"))).toBeGreaterThan(1);

    await env.DB.prepare("DELETE FROM site_snapshots").run();
    warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    expect((await site("/uk?topic=health")).status).toBe(200);
    expect(JSON.parse(String(warn.mock.calls.at(-1)?.[0]))).toMatchObject({ message: "site snapshot missing", lang: "uk" });

    // Fresh again: one row.
    await refreshSite();
    expect(await rowsRead(() => site("/en/g7"))).toBe(1);
  });

});

describe("the top stories from a snapshot", () => {
  const now = new Date("2026-10-30T12:00:00Z");
  const hoursBefore = (h: number) => `${new Date(now.getTime() - h * 3_600_000).toISOString().slice(0, 19)}Z`;
  const candidate = (id: string, country: string, importance: number, hours: number, topics = ["economy"]): TopCandidate => ({ id, country, importance, publishedAt: hoursBefore(hours), topics });
  const article = (id: string, country: string): SnapshotArticle => ({
    id, country, countries: [country], source: { name: country }, headline: id, originalTitle: id, shortSummary: null, decisionType: null,
    topics: ["economy"], publishedAt: hoursBefore(1), dateOnly: false, feedSeq: 1, addedAt: null,
  });
  // Scores now: a 4.98, d 4.17 (a 5 from 40 hours ago), b 3.98, c 3.96; e is older than 72 hours.
  const top = [candidate("c", "US", 4, 2), candidate("b", "DE", 4, 1), candidate("a", "DE", 5, 1), candidate("d", "FR", 5, 40), candidate("e", "GB", 5, 73)];
  const snapshot = (shown: string[]): Snapshot => ({ builtAt: hoursBefore(0), where: { groups: [], countries: [] }, top, articles: shown.map((id) => article(id, top.find((c) => c.id === id)!.country)) });
  const topIds = (s: Snapshot, filter: ListFilter) => snapshotTop(s, filter, now).map((a) => a.id);

  it("picks as topQuery does: best score first, one a source country, 3 in all, within 72 hours as of the request", () => {
    expect(topIds(snapshot(["a", "b", "c", "d", "e"]), { place: null, topic: null })).toEqual(["a", "d", "c"]);
    // Where is one country: up to 3 of its own.
    expect(topIds(snapshot(["a", "b", "c", "d", "e"]), { place: { country: "DE" }, topic: null })).toEqual(["a", "b"]);
    expect(topIds(snapshot(["a", "b", "c", "d", "e"]), { place: { group: "nato" }, topic: null })).toEqual(["a", "d", "c"]);
    expect(topIds(snapshot(["a", "b", "c", "d", "e"]), { place: { group: "nato" }, topic: "health" })).toEqual([]);
    // Older than 72 hours by the time of the request: out, however it scored when the row was built.
    expect(topIds(snapshot(["e"]), { place: { country: "GB" }, topic: null })).toEqual([]);
  });

  it("gives a language the English picks it has, in that order, never one the English feed does not have", () => {
    expect(topIds(snapshot(["c", "a"]), { place: null, topic: null })).toEqual(["a", "c"]);
    expect(topIds(snapshot(["b"]), { place: null, topic: null })).toEqual([]);
  });
});

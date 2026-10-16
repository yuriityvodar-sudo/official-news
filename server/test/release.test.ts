// Release together (#46, Yurii 15 Oct): the feed is the same in every
// language. An article enters it, with one feed_seq, in English and every
// language at once, when each enabled language that is not paused has
// published it or failed it 3 times; a language whose provider is down for 2
// hours is paused automatically and catches up later at the English places.
import { env, exports } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createScheduledController } from "cloudflare:test";
import worker, { CRONS } from "../src/index";
import {
  AUTO_PAUSE_HOURS,
  LANGS,
  RELEASE,
  TRANSLATIONS_PER_RUN,
  TRANSLATOR_ALIVE_MINUTES,
  TRANSLATORS,
  releaseReady,
  runTranslator,
} from "../src/translator";
import {
  type ArticlesPage,
  type Reply,
  answer,
  fakeApis,
  feeds,
  get,
  hideSeed,
  hoursAgo,
  ids,
  insertNews,
  only,
  outcome,
  releasedOrder,
  stored,
  testEnv,
  translation,
} from "./helpers";

/** Spanish on a model of its own in these tests, so an outage of it touches no other language. */
const ES = "groq:es-model";
const providers = { ...TRANSLATORS, es: [ES] };
const run = (fetch: typeof globalThis.fetch, now = new Date(), e = testEnv()) =>
  runTranslator(e, { maxTranslations: TRANSLATIONS_PER_RUN, fetch, now, providers });
const at = (start: Date, minutes: number) => new Date(start.getTime() + minutes * 60_000);
const langRow = (lang: string) =>
  env.DB.prepare("SELECT enabled, paused, paused_reason, down_since FROM translation_langs WHERE lang = ?").bind(lang).first();
/** The translator's last run, as it records it at the start of each run (step_runs). */
const translatorRan = (at: Date) =>
  env.DB.prepare("INSERT INTO step_runs (step, at) VALUES ('translator', ?1) ON CONFLICT (step) DO UPDATE SET at = excluded.at")
    .bind(stored(at))
    .run();
const feedSeq = (id: string) => env.DB.prepare("SELECT feed_seq FROM articles WHERE id = ?").bind(id).first("feed_seq");
const delayed = async (lang: string) => ((await get(`/articles?lang=${lang}`)).body as ArticlesPage).translationsDelayed;
const queue = async () => (await (await exports.default.fetch("https://api.test/queue")).json()) as {
  languages: Record<string, Record<string, unknown>>;
  release: { waiting: number };
};

beforeEach(async () => {
  await hideSeed();
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("release together", () => {
  it("keeps English and every language the same: the same articles, the same order, the same top stories", async () => {
    for (const [i, id] of ["a1", "a2", "a3", "a4"].entries()) await insertNews(id, hoursAgo(5 - i));
    // a1's first Spanish answer is unusable (retried 10 minutes later); at +4 minutes Russian is down for a run.
    const replies: Record<string, Reply[]> = { [ES]: ["not json"] };
    const start = new Date();
    const snapshots: Record<string, string[]>[] = [];
    for (const minutes of [0, 2, 4, 6, 8, 12, 14]) {
      if (minutes === 4) {
        replies["groq:openai/gpt-oss-120b"] = [{ status: 503 }];
        replies["groq:qwen/qwen3.8-27b"] = [answer("uk"), { status: 503 }];
      }
      await run(fakeApis(replies).fetch, at(start, minutes));
      const now = await feeds("uk", "ru", "es");
      // At every moment, each language is exactly the English feed.
      for (const lang of ["uk", "ru", "es"]) expect(now[lang], `${lang} at +${minutes} min`).toEqual(now.en);
      const tops = await Promise.all(
        ["", "?lang=uk", "?lang=ru", "?lang=es"].map(async (q) => ((await get(`/articles${q}`)).body as ArticlesPage).top.map((a) => a.id)),
      );
      for (const top of tops) expect(top).toEqual(tops[0]);
      snapshots.push(now);
    }
    // Everything is out in the end, newest release on top: a1 waited 12 minutes for its Spanish, a3 two
    // minutes for its Russian (still before a4, the older English first).
    expect(snapshots.at(-1)?.en).toEqual(["a1", "a4", "a3", "a2"]);
    expect(snapshots.map((s) => s.en.length)).toEqual([0, 1, 1, 2, 3, 4, 4]);
  });

  it("releases a post that failed 3 times in one language: in English and the others, not in that one, failed in /queue", async () => {
    await insertNews("a1", hoursAgo(1));
    const start = new Date();
    for (const minutes of [0, 11, 32]) await run(fakeApis({ [ES]: ["not json"] }).fetch, at(start, minutes));

    expect(await translation("a1", "es")).toMatchObject({ state: "failed", attempts: 3 });
    expect(await feeds("uk", "ru", "es")).toEqual({ en: ["a1"], uk: ["a1"], ru: ["a1"], es: [] });
    expect((await get("/articles/a1?lang=es")).status).toBe(404);
    const { languages, release } = await queue();
    expect(languages.es).toMatchObject({ failed: 1, published: 0, paused: false });
    expect(release.waiting).toBe(0);
    // Unusable answers are not an outage: Spanish is neither down nor paused.
    expect(await langRow("es")).toMatchObject({ paused: 0, down_since: null });
  });

  it(`pauses a language whose provider is down for ${AUTO_PAUSE_HOURS} hours, releases without it, and lets it catch up in the English order`, async () => {
    await insertNews("a1", hoursAgo(1));
    const t0 = new Date();
    const esDown = () => fakeApis({ [ES]: [{ status: 503 }, { status: 503 }] });

    // Spanish is down: a1 waits, in English too, for up to 2 hours.
    expect(outcome(await run(esDown().fetch, t0))).toEqual(["a1 uk groq:qwen/qwen3.8-27b", "a1 ru groq:openai/gpt-oss-120b", "a1 es failed"]);
    expect(await langRow("es")).toMatchObject({ paused: 0, down_since: stored(t0) });
    await run(esDown().fetch, at(t0, 60));
    await run(esDown().fetch, at(t0, 119));
    expect(await feeds("uk", "ru", "es")).toEqual({ en: [], uk: [], ru: [], es: [] });
    expect(await langRow("es")).toMatchObject({ paused: 0 });

    // Down for more than 2 hours: paused automatically, and a1 is released without it.
    await run(esDown().fetch, at(t0, 121));
    expect(await langRow("es")).toEqual({ enabled: 1, paused: 1, paused_reason: `auto: provider down since ${stored(t0)}`, down_since: stored(t0) });
    expect(await feeds("uk", "ru", "es")).toEqual({ en: ["a1"], uk: ["a1"], ru: ["a1"], es: [] });
    expect(await delayed("es")).toBe(true);
    expect(await delayed("uk")).toBe(false);
    expect((await queue()).languages.es).toMatchObject({ paused: true, pausedReason: `auto: provider down since ${stored(t0)}` });

    // Paused, it is still probed with one claim a run, and nothing waits for it.
    await insertNews("a2", hoursAgo(0.5));
    const probe = esDown();
    const results = await run(probe.fetch, at(t0, 123));
    expect(results.filter((r) => r.lang === "es")).toHaveLength(1);
    expect(probe.requests.filter((r) => r.lang === "es")).toHaveLength(1);
    expect(await feeds("uk", "ru", "es")).toEqual({ en: ["a2", "a1"], uk: ["a2", "a1"], ru: ["a2", "a1"], es: [] });

    // The provider is back: its first answer unpauses Spanish, which catches up at the English places.
    const back = await run(fakeApis().fetch, at(t0, 200));
    expect(back.filter((r) => r.lang === "es").map((r) => r.ok)).toEqual([true]);
    expect(await langRow("es")).toEqual({ enabled: 1, paused: 0, paused_reason: null, down_since: null });
    expect(await delayed("es")).toBe(false);
    for (let i = 0; i < 3; i++) await run(fakeApis().fetch, at(t0, 202 + 2 * i));
    expect(await feeds("uk", "ru", "es")).toEqual({ en: ["a2", "a1"], uk: ["a2", "a1"], ru: ["a2", "a1"], es: ["a2", "a1"] });
    // Unpaused, it is waited for again.
    await insertNews("a3", hoursAgo(0.2));
    await run(fakeApis({ [ES]: [{ status: 503 }] }).fetch, at(t0, 210));
    expect(await ids("/articles")).toEqual(["a2", "a1"]);
  });

  it("never probes a language paused by hand; an automatic pause ends only with an answer for that language", async () => {
    await insertNews("a1", hoursAgo(1));
    await env.DB.prepare("UPDATE translation_langs SET paused = 1, paused_reason = 'manual' WHERE lang = 'es'").run();
    const since = "2026-10-15T08:00:00Z";
    await env.DB.prepare("UPDATE translation_langs SET paused = 1, paused_reason = ?1, down_since = ?2 WHERE lang = 'ru'")
      .bind(`auto: provider down since ${since}`, since)
      .run();

    // Russian is probed and its providers are still down; Ukrainian's answer does not unpause it.
    const ruDown = fakeApis({ "groq:openai/gpt-oss-120b": [{ status: 503 }], "groq:qwen/qwen3.8-27b": [answer("uk"), { status: 503 }] });
    expect(outcome(await run(ruDown.fetch))).toEqual(["a1 uk groq:qwen/qwen3.8-27b", "a1 ru failed"]);
    expect(ruDown.requests.some((r) => r.lang === "es")).toBe(false);
    expect(await langRow("ru")).toMatchObject({ paused: 1, paused_reason: `auto: provider down since ${since}`, down_since: since });
    // Both paused: a1 is out in English and Ukrainian.
    expect(await feeds("uk", "ru", "es")).toEqual({ en: ["a1"], uk: ["a1"], ru: [], es: [] });

    const later = new Date(Date.now() + 3 * 60_000);
    expect(outcome(await run(fakeApis().fetch, later))).toEqual(["a1 ru groq:openai/gpt-oss-120b"]);
    expect(await langRow("ru")).toEqual({ enabled: 1, paused: 0, paused_reason: null, down_since: null });
    expect(await langRow("es")).toMatchObject({ paused: 1, paused_reason: "manual" });
    expect(await feeds("ru", "es")).toEqual({ en: ["a1"], ru: ["a1"], es: [] });
  });

  it("keeps a manual pause made while a run translates that language, also once its provider answers", async () => {
    await insertNews("a1", hoursAgo(1));
    // Spanish was down a while ago, so its answer now would clear that.
    await env.DB.prepare("UPDATE translation_langs SET down_since = ? WHERE lang = 'es'").bind(hoursAgo(1)).run();
    const apis = fakeApis();
    const pauseMeanwhile = (async (input: RequestInfo | URL, init?: RequestInit) => {
      if (String(init?.body).includes("into Spanish")) {
        await env.DB.prepare("UPDATE translation_langs SET paused = 1, paused_reason = 'manual' WHERE lang = 'es'").run();
      }
      return apis.fetch(input, init);
    }) as typeof globalThis.fetch;

    expect(outcome(await run(pauseMeanwhile))).toContain(`a1 es ${ES}`);
    expect(await langRow("es")).toEqual({ enabled: 1, paused: 1, paused_reason: "manual", down_since: null });
  });

  it("does not release an article on translations of an older English", async () => {
    await insertNews("a1", hoursAgo(1));
    await only("uk");
    await translatorRan(new Date());
    // Published for the English summarized an hour ago; then the English is summarized again, before any run queues it.
    await env.DB.prepare(
      `INSERT INTO article_translations (article_id, lang, headline, short_summary, summary, model, source_summarized_at,
                                         attempts_source, lang_seq, translated_at, published_at, state)
       SELECT id, 'uk', 'Заголовок', 'Коротко.', 'Підсумок.', 'groq:x', summarized_at, summarized_at, 1, ?1, ?1, 'published' FROM articles WHERE id = 'a1'`,
    )
      .bind(stored(new Date()))
      .run();
    await env.DB.prepare("UPDATE articles SET summarized_at = ? WHERE id = 'a1'").bind(stored(new Date())).run();
    expect(await releaseReady(env, new Date())).toEqual([]);
    // Once the new English is translated, it is.
    await env.DB.prepare("UPDATE article_translations SET source_summarized_at = ?1, attempts_source = ?1 WHERE article_id = 'a1'")
      .bind(await env.DB.prepare("SELECT summarized_at FROM articles WHERE id = 'a1'").first("summarized_at"))
      .run();
    expect(await releaseReady(env, new Date())).toEqual(["a1"]);
  });

  it(`counts a language without its provider key as down, and releases without it after ${AUTO_PAUSE_HOURS} hours`, async () => {
    await insertNews("a1", hoursAgo(1));
    const t0 = new Date();
    const noSpanish = testEnv();
    const runWithout = (now: Date) => runTranslator(noSpanish, { maxTranslations: 4, fetch: fakeApis().fetch, now, providers: { ...TRANSLATORS, es: [] } });
    await runWithout(t0);
    expect(await langRow("es")).toMatchObject({ down_since: stored(t0), paused: 0 });
    expect(await ids("/articles")).toEqual([]);
    await runWithout(at(t0, 121));
    expect(await langRow("es")).toMatchObject({ paused: 1, paused_reason: `auto: provider down since ${stored(t0)}` });
    expect(await feeds("uk", "ru", "es")).toEqual({ en: ["a1"], uk: ["a1"], ru: ["a1"], es: [] });
  });

  it("with no language enabled, releases at once, also in a run with nothing to translate and no keys", async () => {
    await only();
    await insertNews("a1", hoursAgo(2));
    await insertNews("a2", hoursAgo(1));
    const log = vi.spyOn(console, "log");
    expect(await runTranslator(testEnv(null, undefined, null), { maxTranslations: 4 })).toEqual([]);
    expect(await ids("/articles")).toEqual(["a2", "a1"]);
    expect(log).toHaveBeenCalledWith(expect.stringContaining('"released":["a1","a2"]'));
    // Released oldest summarized first: numbers in that order.
    expect(await releasedOrder()).toEqual(["a1", "a2"]);
  });

  it("releases many waiting articles in one run, one feed_seq each, oldest summarized first", async () => {
    await only();
    for (let i = 0; i < 12; i++) await insertNews(`n${String(i).padStart(2, "0")}`, hoursAgo(20 - i));
    await runTranslator(testEnv(), { maxTranslations: 4, fetch: fakeApis().fetch });
    const order = await releasedOrder();
    expect(order).toEqual(Array.from({ length: 12 }, (_, i) => `n${String(i).padStart(2, "0")}`));
    const { results } = await env.DB.prepare("SELECT feed_seq FROM articles WHERE id LIKE 'n%' ORDER BY feed_seq").all<{ feed_seq: number }>();
    const seqs = results.map((r) => r.feed_seq);
    expect(new Set(seqs).size).toBe(12);
    expect(seqs.at(-1)! - seqs[0]).toBe(11);
  });

  it("finds the waiting articles through their partial index", async () => {
    const { results } = await env.DB.prepare(`EXPLAIN QUERY PLAN ${RELEASE}`)
      .bind(stored(new Date()), hoursAgo(7 * 24), JSON.stringify(LANGS), hoursAgo(1))
      .all<{ detail: string }>();
    const plan = results.map((r) => r.detail).join("; ");
    expect(plan).toMatch(/SCAN u USING (COVERING )?INDEX articles_unreleased/);
    expect(plan).toContain("SEARCH r USING INDEX sqlite_autoindex_step_runs_1 (step=?)");
    expect(plan).toContain("SEARCH t USING INDEX sqlite_autoindex_article_translations_1 (article_id=? AND lang=?)");
    expect(plan).toContain("articles_feed_seq");
    expect(plan).not.toContain("TEMP B-TREE");
  });

  describe("while the translator is not running", () => {
    // Its new cron trigger can take about an hour to start firing after a deploy (#50): the
    // English feed goes on, and the languages fill in later at the English places (Roman, #49).
    it(`releases at once when the translator has not run for ${TRANSLATOR_ALIVE_MINUTES} minutes, or never`, async () => {
      await insertNews("a1", hoursAgo(1));
      await only("uk", "ru", "es");
      expect(await releaseReady(env, new Date())).toEqual(["a1"]);

      await insertNews("a2", hoursAgo(1));
      await translatorRan(new Date(Date.now() - (TRANSLATOR_ALIVE_MINUTES - 1) * 60_000));
      expect(await releaseReady(env, new Date())).toEqual([]);
      await translatorRan(new Date(Date.now() - (TRANSLATOR_ALIVE_MINUTES + 1) * 60_000));
      expect(await releaseReady(env, new Date())).toEqual(["a2"]);
    });

    it("releases from the summarizer's scheduled run, also one with nothing to summarize", async () => {
      await insertNews("a1", hoursAgo(1));
      await only("uk", "ru", "es");
      const log = vi.spyOn(console, "log").mockImplementation(() => {});
      await worker.scheduled(createScheduledController({ cron: CRONS.summarizer }), env);
      expect(await feedSeq("a1")).toEqual(expect.any(Number));
      expect(log.mock.calls.map((c) => JSON.parse(String(c[0])))).toContainEqual({ message: "summarizer release", released: ["a1"] });

      // Once the translator runs, the summarizer's release waits for the translations too.
      await insertNews("a2", hoursAgo(1));
      await translatorRan(new Date());
      await worker.scheduled(createScheduledController({ cron: CRONS.summarizer }), env);
      expect(await feedSeq("a2")).toBeNull();
    });

    it("records each translator run, so the release waits for it from its first run", async () => {
      await insertNews("a1", hoursAgo(1));
      await only("uk");
      const start = new Date();
      await run(fakeApis({ "groq:qwen/qwen3.8-27b": [{ status: 503 }], "groq:openai/gpt-oss-120b": [{ status: 503 }] }).fetch, start);
      expect(await env.DB.prepare("SELECT at FROM step_runs WHERE step = 'translator'").first("at")).toBe(stored(start));
      expect(await feedSeq("a1")).toBeNull();
    });
  });

  it("goes on after an unexpected error in one translation: the other languages are stored and the run releases", async () => {
    await insertNews("a2", hoursAgo(1));
    await only("uk", "ru", "es");
    // The first translation's store fails in D1, as an outage of the database would.
    const prepare = env.DB.prepare.bind(env.DB);
    let failed = false;
    vi.spyOn(env.DB, "prepare").mockImplementation((sql: string) => {
      if (!failed && sql.includes("SET headline = ?1")) {
        failed = true;
        throw new Error("D1_ERROR: storage operation exceeded timeout");
      }
      return prepare(sql);
    });
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    const results = await run(fakeApis().fetch);
    expect(results.filter((r) => r.ok)).toHaveLength(2);
    expect(results.filter((r) => r.error?.startsWith("unexpected: D1_ERROR"))).toHaveLength(1);
    expect(log.mock.calls.map((c) => JSON.parse(String(c[0])).message)).toContain("translator run");
  });
});

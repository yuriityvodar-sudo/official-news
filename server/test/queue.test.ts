// The explicit translation queue (#46) in all four languages: states, the
// switch per language, Spanish on Groq, German through Z.ai when it is turned
// on (off by default), the state log, the counts, and GET /queue.
import { env, exports } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ENQUEUE, LANGS, MAX_ATTEMPTS, STATES, TRANSLATIONS_PER_RUN, runTranslator } from "../src/translator";
import { MAX_RETRY_MINUTES, RETRY_OUTAGE_MINUTES, nextAttemptAt } from "../src/translator/queue";
import { GROQ_URL, ZAI_URL } from "../src/translator/providers";
import {
  GLM_45,
  GLM_47,
  GPT_OSS,
  GPT_OSS_20B,
  QWEN,
  TRANSLATED,
  type ArticlesPage,
  type Reply,
  answer,
  chat,
  d1Rows,
  events,
  fakeApis,
  feeds,
  get,
  hideSeed,
  hoursAgo,
  ids,
  inMinutes,
  insertNews,
  minutesAgo,
  outcome,
  rowsRead,
  stored,
  testEnv,
  translation,
} from "./helpers";

beforeEach(async () => {
  await hideSeed();
});

afterEach(() => {
  vi.restoreAllMocks();
});

const run = (fetch: typeof globalThis.fetch, options: { now?: Date; env?: ReturnType<typeof testEnv> } = {}) =>
  runTranslator(options.env ?? testEnv(), { maxTranslations: TRANSLATIONS_PER_RUN, fetch, now: options.now });

/** The counts the triggers keep, as `lang state n`, next to the same counted from the table. */
async function counts() {
  const kept = await env.DB.prepare("SELECT lang, state, n FROM translation_counts WHERE n <> 0 ORDER BY lang, state").all();
  const real = await env.DB.prepare("SELECT lang, state, COUNT(*) AS n FROM article_translations GROUP BY lang, state ORDER BY lang, state").all();
  return { kept: kept.results, real: real.results };
}

const setLang = (lang: string, column: "enabled" | "paused", value: 0 | 1) =>
  env.DB.prepare(`UPDATE translation_langs SET ${column} = ? WHERE lang = ?`).bind(value, lang).run();

/** The languages on by default: German is off (Z.ai blocks Cloudflare Workers, 15 Oct). */
const ON = ["uk", "ru", "es"] as const;

describe("the translation queue in four languages", () => {
  it("queues every news article for every enabled language and publishes it in each, Spanish through Groq, German off", async () => {
    await insertNews("a1", hoursAgo(2));
    await insertNews("a2", hoursAgo(1));
    // A small wait in every answer, so two requests at once would show.
    const apis = fakeApis({}, { delayMs: 5 });

    const first = await run(apis.fetch);
    const second = await run(apis.fetch);

    // One article in each enabled language per run, oldest English first.
    expect(TRANSLATIONS_PER_RUN).toBe(4);
    expect(outcome(first)).toEqual([`a1 uk ${QWEN}`, `a1 ru ${GPT_OSS}`, `a1 es ${GPT_OSS_20B}`]);
    expect(outcome(second)).toEqual([`a2 uk ${QWEN}`, `a2 ru ${GPT_OSS}`, `a2 es ${GPT_OSS_20B}`]);
    // Groq: one request at a time; Spanish asks gpt-oss-20b, with little reasoning, in JSON mode.
    expect(apis.mostAtOnce.groq).toBe(1);
    expect(apis.requests.some((r) => r.url === ZAI_URL)).toBe(false);
    const spanish = apis.requests.find((r) => r.lang === "es");
    expect(spanish?.url).toBe(GROQ_URL);
    expect(spanish?.authorization).toBe("Bearer test-key");
    expect(spanish?.body).toMatchObject({
      model: "openai/gpt-oss-20b",
      reasoning_effort: "low",
      response_format: { type: "json_object" },
      temperature: 0.2,
      max_tokens: 700,
    });
    const [system] = spanish?.body.messages as { content: string }[];
    expect(system.content).toContain("from English into Spanish");
    expect(system.content).toContain("1.250.000; 3,5 %");

    for (const lang of ON) {
      expect(await ids(`/articles?lang=${lang}`)).toEqual(["a2", "a1"]);
      expect(await translation("a1", lang)).toMatchObject({ state: "published", headline: TRANSLATED[lang].headline });
    }
    expect(await ids("/articles")).toEqual(["a2", "a1"]);
    // German is not queued while it is off.
    expect(await translation("a1", "de")).toBeNull();
    expect((await get("/articles/a1?lang=de")).status).toBe(404);
    // Every change of state is logged with its time.
    const log = await events("a1", "es");
    expect(log.map((e) => [e.state, e.detail])).toEqual([
      ["queued", null],
      ["translating", null],
      ["published", GPT_OSS_20B],
    ]);
    for (const e of log) expect(e.at).toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
    expect(await counts()).toMatchObject({ kept: (await counts()).real });
  });

  it("Spanish falls back to gpt-oss-120b when gpt-oss-20b is down", async () => {
    await insertNews("a1", hoursAgo(1));
    const apis = fakeApis({ [GPT_OSS_20B]: [{ status: 429 }] });
    expect(outcome(await run(apis.fetch))).toEqual([`a1 uk ${QWEN}`, `a1 ru ${GPT_OSS}`, `a1 es ${GPT_OSS}`]);
    expect(await translation("a1", "es")).toMatchObject({ state: "published", model: GPT_OSS, attempts: 0 });
  });

  describe("German through Z.ai, when it is turned on", () => {
    beforeEach(async () => {
      await setLang("de", "enabled", 1);
    });

    it("publishes German through glm-4.5-flash, one request at a time, thinking off", async () => {
      await insertNews("a1", hoursAgo(1));
      const apis = fakeApis({}, { delayMs: 5 });
      expect(outcome(await run(apis.fetch))).toEqual([`a1 uk ${QWEN}`, `a1 ru ${GPT_OSS}`, `a1 es ${GPT_OSS_20B}`, `a1 de ${GLM_45}`]);
      expect(apis.mostAtOnce.zai).toBe(1);
      const german = apis.requests.find((r) => r.lang === "de");
      expect(german?.url).toBe(ZAI_URL);
      expect(german?.authorization).toBe("Bearer zai-test-key");
      expect(german?.body).toMatchObject({ model: "glm-4.5-flash", thinking: { type: "disabled" }, response_format: { type: "json_object" } });
      expect((await get("/articles/a1?lang=de")).body).toMatchObject({ lang: "de", headline: TRANSLATED.de.headline });
    });

    it.each([
      ["1302 (too many requests at once)", { status: 429, body: { error: { code: "1302", message: "High concurrency" } } }, "HTTP 429 1302"],
      ["1305 (overloaded)", { status: 429, body: { error: { code: "1305", message: "Overloaded" } } }, "HTTP 429 1305"],
      ["1234 (network)", { status: 500, body: { error: { code: "1234", message: "Network error" } } }, "HTTP 500 1234"],
      ["a plain 429", { status: 429 }, "HTTP 429"],
      ["a 405 block page", { status: 405, body: "<html>blocked</html>" }, "HTTP 405"],
      ["a 503", { status: 503 }, "HTTP 503"],
      ["an error code with HTTP 200", { status: 200, body: { error: { code: "1305" } } }, "HTTP 200 1305"],
      ["a network error", new Error("connection reset"), "request failed: connection reset"],
    ])("when both Z.ai models fail with %s, German is retrying, without an attempt", async (_, reply, why) => {
      await insertNews("a1", hoursAgo(1));
      const apis = fakeApis({ [GLM_45]: [reply as Reply], [GLM_47]: [reply as Reply] });
      const now = new Date();

      const results = await run(apis.fetch, { now });

      expect(outcome(results)).toEqual([`a1 uk ${QWEN}`, `a1 ru ${GPT_OSS}`, `a1 es ${GPT_OSS_20B}`, "a1 de failed"]);
      // glm-4.5-flash, then glm-4.7-flash.
      expect(apis.requests.filter((r) => r.url === ZAI_URL).map((r) => `${r.lang} ${r.model}`)).toEqual(["de glm-4.5-flash", "de glm-4.7-flash"]);
      const row = await translation("a1", "de");
      expect(row).toMatchObject({ state: "retrying", attempts: 0, outage_retries: 1, next_attempt_at: stored(new Date(now.getTime() + 2 * 60_000)) });
      expect(row?.last_error).toContain(`${GLM_45}: ${why}`);
      // The other languages are not affected.
      expect(await translation("a1", "es")).toMatchObject({ state: "published" });
      // The next run, with Z.ai back, publishes it.
      expect(outcome(await run(fakeApis().fetch, { now: new Date(now.getTime() + 2 * 60_000) }))).toEqual([`a1 de ${GLM_45}`]);
    });

    it("falls back to glm-4.7-flash when glm-4.5-flash is down", async () => {
      await insertNews("a1", hoursAgo(1));
      const apis = fakeApis({ [GLM_45]: [{ status: 429, body: { error: { code: "1302" } } }] });

      expect(outcome(await run(apis.fetch))).toEqual([`a1 uk ${QWEN}`, `a1 ru ${GPT_OSS}`, `a1 es ${GPT_OSS_20B}`, `a1 de ${GLM_47}`]);
      expect(await translation("a1", "de")).toMatchObject({ state: "published", model: GLM_47, attempts: 0 });
    });

    it.each([
      ["error 1301", { status: 400, body: { error: { code: "1301", message: "Content security warning" } } }],
      ["finish_reason sensitive", { status: 200, body: chat("", "sensitive") }],
    ])("counts Z.ai's content filter (%s) as an unusable answer, without trying the other model", async (_, reply) => {
      await insertNews("a1", hoursAgo(1));
      const apis = fakeApis({ [GLM_45]: [reply] });

      const results = await run(apis.fetch);

      expect(results.find((r) => r.lang === "de")).toMatchObject({ ok: false, provider: GLM_45, error: "content filter" });
      expect(await translation("a1", "de")).toMatchObject({ state: "retrying", attempts: 1, last_error: `${GLM_45}: content filter` });
      expect(apis.requests.filter((r) => r.lang === "de")).toHaveLength(1);
    });

    it("without ZAI_API_KEY, German waits in the queue, counted as down, while the others are published", async () => {
      await insertNews("a1", hoursAgo(1));
      const apis = fakeApis();
      const log = vi.spyOn(console, "log");
      const now = new Date();

      expect(outcome(await run(apis.fetch, { env: testEnv("test-key", undefined, null), now }))).toEqual([
        `a1 uk ${QWEN}`,
        `a1 ru ${GPT_OSS}`,
        `a1 es ${GPT_OSS_20B}`,
      ]);

      expect(apis.requests.some((r) => r.url === ZAI_URL)).toBe(false);
      expect(await translation("a1", "de")).toMatchObject({ state: "queued", claimed_at: null });
      expect(log).toHaveBeenCalledWith(expect.stringContaining('"waiting":["de"]'));
      // A language that cannot translate is down from now on: after 2 hours the release stops waiting for it.
      expect(await env.DB.prepare("SELECT down_since FROM translation_langs WHERE lang = 'de'").first("down_since")).toBe(stored(now));
      expect(await ids("/articles")).toEqual([]);
      // Once the key is there, it is translated, no longer down, and the article is released in all four.
      expect(outcome(await run(fakeApis().fetch))).toEqual([`a1 de ${GLM_45}`]);
      expect(await env.DB.prepare("SELECT down_since FROM translation_langs WHERE lang = 'de'").first("down_since")).toBeNull();
      for (const lang of LANGS) expect(await ids(`/articles?lang=${lang}`)).toEqual(["a1"]);
    });

    it("sends Z.ai one German request a run, also while the other languages are paused", async () => {
      await insertNews("a1", hoursAgo(2));
      await insertNews("a2", hoursAgo(1));
      for (const lang of ON) await setLang(lang, "paused", 1);
      const apis = fakeApis();

      expect(outcome(await run(apis.fetch))).toEqual([`a1 de ${GLM_45}`]);
      expect(apis.requests.map((r) => `${r.lang} ${r.model}`)).toEqual(["de glm-4.5-flash"]);
      expect(outcome(await run(apis.fetch))).toEqual([`a2 de ${GLM_45}`]);
    });

    it("claims one article per language a run, so German retrying in a Z.ai outage holds back no other language", async () => {
      for (const [i, id] of ["o1", "o2", "o3"].entries()) await insertNews(id, hoursAgo(5 - i));
      await insertNews("new", hoursAgo(1));
      const now = new Date();
      await env.DB.batch(LANGS.map((lang) => env.DB.prepare(ENQUEUE).bind(lang, stored(now), hoursAgo(8 * 24), hoursAgo(7 * 24))));
      // The older news is done in the other languages (out of the way here) and due again in German.
      await env.DB.prepare("UPDATE article_translations SET state = 'skipped' WHERE article_id <> 'new' AND lang <> 'de'").run();
      await env.DB.prepare("UPDATE article_translations SET state = 'retrying', next_attempt_at = ?1 WHERE article_id <> 'new' AND lang = 'de'")
        .bind(stored(now))
        .run();
      const zaiDown = fakeApis({ [GLM_45]: [{ status: 503 }], [GLM_47]: [{ status: 503 }] });

      const results = await run(zaiDown.fetch, { now });

      // Not the four oldest due ones (all German): the oldest of each language.
      expect(outcome(results)).toEqual(["o1 de failed", `new uk ${QWEN}`, `new ru ${GPT_OSS}`, `new es ${GPT_OSS_20B}`]);
      expect(zaiDown.requests.filter((r) => r.url === ZAI_URL).map((r) => `${r.lang} ${r.model}`)).toEqual(["de glm-4.5-flash", "de glm-4.7-flash"]);
      expect(await translation("new", "de")).toMatchObject({ state: "queued" });
    });
  });

  it("queues a paused language but claims nothing of it, and the release does not wait for it; resumed, it goes on", async () => {
    await insertNews("a1", hoursAgo(1));
    await setLang("es", "paused", 1);

    expect(outcome(await run(fakeApis().fetch))).toEqual([`a1 uk ${QWEN}`, `a1 ru ${GPT_OSS}`]);
    expect(await translation("a1", "es")).toMatchObject({ state: "queued" });
    expect(await feeds("uk", "ru", "es")).toEqual({ en: ["a1"], uk: ["a1"], ru: ["a1"], es: [] });
    expect(await run(fakeApis().fetch)).toEqual([]);

    await setLang("es", "paused", 0);
    expect(outcome(await run(fakeApis().fetch))).toEqual([`a1 es ${GPT_OSS_20B}`]);
    expect(await ids("/articles?lang=es")).toEqual(["a1"]);
  });

  it("does not queue a disabled language; a language with nothing queued yet gets the feed's 7 days once enabled", async () => {
    await insertNews("a1", hoursAgo(30));
    await insertNews("old", hoursAgo(8 * 24));
    await run(fakeApis().fetch);
    expect(await translation("a1", "de")).toBeNull();

    await setLang("de", "enabled", 1);
    await insertNews("a2", hoursAgo(1));
    // German takes a2 first: it is not released yet, and every feed waits for it. a1 is already out.
    expect(outcome(await run(fakeApis().fetch))).toEqual([`a2 uk ${QWEN}`, `a2 ru ${GPT_OSS}`, `a2 es ${GPT_OSS_20B}`, `a2 de ${GLM_45}`]);
    expect(outcome(await run(fakeApis().fetch))).toEqual([`a1 de ${GLM_45}`]);
    expect(await translation("old", "de")).toBeNull();
    expect(await ids("/articles?lang=de")).toEqual(["a2", "a1"]);
  });

  it("waits longer after each try no provider answered: 2, 4, 8 … up to 60 minutes, never counting an attempt", async () => {
    const start = new Date("2026-10-15T12:00:00Z");
    expect([0, 1, 2, 3, 4, 5, 6, 9].map((tries) => nextAttemptAt(start, RETRY_OUTAGE_MINUTES, tries).slice(11, 16))).toEqual([
      "12:02",
      "12:04",
      "12:08",
      "12:16",
      "12:32",
      "13:00",
      "13:00",
      "13:00",
    ]);
    expect(MAX_RETRY_MINUTES).toBe(60);

    await insertNews("a1", hoursAgo(1));
    await setLang("uk", "enabled", 0);
    await setLang("ru", "enabled", 0);
    let now = new Date();
    for (const wait of [2, 4, 8]) {
      const down = fakeApis({ [GPT_OSS_20B]: [{ status: 429 }], [GPT_OSS]: [{ status: 429 }] });
      await run(down.fetch, { now });
      expect(await translation("a1", "es")).toMatchObject({ state: "retrying", attempts: 0, next_attempt_at: stored(new Date(now.getTime() + wait * 60_000)) });
      // Not before its time.
      expect(await run(fakeApis().fetch, { now: new Date(now.getTime() + (wait - 1) * 60_000) })).toEqual([]);
      now = new Date(now.getTime() + wait * 60_000);
    }
    expect(outcome(await run(fakeApis().fetch, { now }))).toEqual([`a1 es ${GPT_OSS_20B}`]);
    expect(await translation("a1", "es")).toMatchObject({ state: "published", attempts: 0, outage_retries: 0 });
  });

  it("enabling a language with a backlog holds back neither the other languages nor the new articles", async () => {
    // More backlog than a run reads per language (CLAIM_WINDOW), so the new article is found by its own lane.
    const backlog = ["b1", "b2", "b3", "b4", "b5", "b6"];
    for (const [i, id] of backlog.entries()) await insertNews(id, hoursAgo(30 - i));
    // The others are done with the backlog (out of the way here).
    for (const _ of backlog) await run(fakeApis().fetch);
    await setLang("de", "enabled", 1);
    await insertNews("new", hoursAgo(1));

    // German takes the new article first, so it is released in all four at once; then its backlog, oldest first.
    expect(outcome(await run(fakeApis().fetch))).toEqual([`new uk ${QWEN}`, `new ru ${GPT_OSS}`, `new es ${GPT_OSS_20B}`, `new de ${GLM_45}`]);
    const english = ["new", ...[...backlog].reverse()];
    expect(await feeds("de")).toEqual({ en: english, de: ["new"] });
    expect(outcome(await run(fakeApis().fetch))).toEqual([`b1 de ${GLM_45}`]);
    expect(outcome(await run(fakeApis().fetch))).toEqual([`b2 de ${GLM_45}`]);
    // It fills in at the English places.
    expect(await feeds("de")).toEqual({ en: english, de: ["new", "b2", "b1"] });
  });

  it("re-summarized: published, then updating with the old text shown, then published again; failed after 3 unusable answers", async () => {
    await insertNews("a1", hoursAgo(1));
    await run(fakeApis().fetch);
    const old = await translation("a1", "es");
    await env.DB.prepare("UPDATE articles SET summarized_at = ? WHERE id = 'a1'").bind(minutesAgo(1)).run();
    await env.DB.batch(LANGS.map((lang) => env.DB.prepare(ENQUEUE).bind(lang, minutesAgo(0), hoursAgo(8 * 24), hoursAgo(7 * 24))));

    for (const lang of ON) expect(await translation("a1", lang)).toMatchObject({ state: "updating", headline: TRANSLATED[lang].headline });
    expect(await ids("/articles?lang=es")).toEqual(["a1"]);

    // Spanish gets three unusable answers (10 and 20 minutes apart); the others are published again.
    const bad = () => fakeApis({ [GPT_OSS_20B]: ["not json"] });
    await run(bad().fetch);
    expect(await translation("a1", "es")).toMatchObject({ state: "retrying", attempts: 1, headline: old?.headline });
    expect(await ids("/articles?lang=es")).toEqual(["a1"]);
    await run(bad().fetch, { now: inMinutes(11) });
    await run(bad().fetch, { now: inMinutes(32) });
    const failed = await translation("a1", "es");
    expect(failed).toMatchObject({ state: "failed", attempts: MAX_ATTEMPTS, queued_at: null });
    expect(failed?.last_error).toContain(`${GPT_OSS_20B}: the answer is not valid JSON`);
    expect(await ids("/articles?lang=es")).toEqual([]);
    for (const lang of ["uk", "ru"] as const) expect(await translation("a1", lang)).toMatchObject({ state: "published" });
    // Still in the English feed and the others: it was released before.
    expect(await feeds("uk", "ru")).toEqual({ en: ["a1"], uk: ["a1"], ru: ["a1"] });

    expect((await events("a1", "es")).map((e) => `${e.state} ${e.attempts}`)).toEqual([
      "queued 0",
      "translating 0",
      "published 0",
      "updating 0",
      "translating 0",
      "retrying 1",
      "translating 1",
      "retrying 2",
      "translating 2",
      "failed 3",
    ]);
  });

  it("logs a new English for a translation still queued, though its state stays the same", async () => {
    await insertNews("a1", hoursAgo(1));
    await setLang("es", "paused", 1);
    await run(fakeApis().fetch);
    const newer = minutesAgo(1);
    await env.DB.prepare("UPDATE articles SET summarized_at = ? WHERE id = 'a1'").bind(newer).run();
    await run(fakeApis().fetch);
    expect(await translation("a1", "es")).toMatchObject({ state: "queued", attempts_source: newer });
    expect((await events("a1", "es")).map((e) => e.state)).toEqual(["queued", "queued"]);
  });

  it("a run that lost its claim changes nothing with its unusable answer or its outage", async () => {
    await insertNews("a1", hoursAgo(1));
    await setLang("es", "enabled", 0);
    await setLang("de", "enabled", 0);
    const later = minutesAgo(-1);
    // Ukrainian gets an unusable answer from Qwen; Russian finds both Groq models down.
    const apis = fakeApis({ [QWEN]: ["not json", { status: 429 }], [GPT_OSS]: [{ status: 429 }] });
    let first = true;
    const slowFetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
      if (first) {
        first = false;
        // While this run waits, its claims run out and another run takes them.
        await env.DB.prepare("UPDATE article_translations SET claimed_at = ?, state_at = ? WHERE article_id = 'a1'").bind(later, later).run();
      }
      return apis.fetch(input, init);
    }) as typeof globalThis.fetch;

    const results = await run(slowFetch);

    expect(results.map((r) => `${r.lang} ${r.ok}`)).toEqual(["uk false", "ru false"]);
    for (const lang of ["uk", "ru"] as const) {
      expect(await translation("a1", lang)).toMatchObject({ state: "translating", claimed_at: later, attempts: 0, outage_retries: 0 });
    }
  });

  it("keeps the counts per state equal to the table through every kind of change", async () => {
    for (const [i, id] of ["a1", "a2", "a3", "a4"].entries()) await insertNews(id, hoursAgo(5 - i));
    await run(fakeApis({ [GPT_OSS_20B]: [{ status: 429 }], [GPT_OSS]: [{ status: 429 }, { status: 429 }] }).fetch);
    await run(fakeApis({ [QWEN]: ["not json"], [GPT_OSS]: ["not json"] }).fetch);
    await env.DB.prepare("UPDATE articles SET is_news = 0 WHERE id = 'a4'").run();
    await env.DB.prepare("UPDATE articles SET summarized_at = ? WHERE id = 'a1'").bind(minutesAgo(1)).run();
    await run(fakeApis().fetch, { now: inMinutes(3) });
    await env.DB.prepare("DELETE FROM article_translations WHERE article_id = 'a3' AND lang = 'uk'").run();

    const { kept, real } = await counts();
    expect(kept).toEqual(real);
    expect(new Set(real.map((r) => r.state)).size).toBeGreaterThan(2);
  });

  it("drops the state log older than 30 days", async () => {
    await env.DB.batch([
      env.DB.prepare("INSERT INTO translation_events (article_id, lang, state, at, attempts) VALUES ('x', 'uk', 'queued', ?, 0)").bind(hoursAgo(31 * 24)),
      env.DB.prepare("INSERT INTO translation_events (article_id, lang, state, at, attempts) VALUES ('y', 'uk', 'queued', ?, 0)").bind(hoursAgo(29 * 24)),
    ]);
    await run(fakeApis().fetch);
    const { results } = await env.DB.prepare("SELECT article_id FROM translation_events ORDER BY article_id").all();
    expect(results).toEqual([{ article_id: "y" }]);
  });

  it("writes a few dozen D1 rows per article and language", async () => {
    await insertNews("a1", hoursAgo(1));
    const rows = await d1Rows(() => run(fakeApis().fetch));
    // 3 languages: queued, translating, published, each with its log row, counts and indexes, and the release.
    console.log(JSON.stringify({ rowsPerArticleIn4Languages: rows }));
    expect(rows.written).toBeLessThanOrEqual(3 * 40);
  });
});

interface QueueBody {
  languages: Record<string, Record<string, number | boolean | string | null>>;
  release: { waiting: number; oldestWaitingAgeMinutes: number | null };
}

describe("GET /queue", () => {
  it("shows per language its switch, the count per state, the last 24 hours, the oldest waiting and the last published", async () => {
    await insertNews("a1", hoursAgo(3));
    await insertNews("a2", hoursAgo(2));
    await setLang("es", "paused", 1);
    // The first run publishes a1 in uk and ru (one article in each language; Spanish is paused, German off),
    // and releases it. The second publishes a2 in uk, and a2 in ru is retrying (GPT-OSS and then Qwen are
    // down), so a2 waits for its release.
    await run(fakeApis().fetch);
    const now = new Date();
    await run(fakeApis({ [QWEN]: [answer("uk"), { status: 429 }], [GPT_OSS]: [{ status: 429 }] }).fetch, { now });
    await env.DB.prepare("UPDATE article_translations SET queued_at = ? WHERE article_id = 'a1' AND lang = 'es'").bind(minutesAgo(90)).run();

    const response = await exports.default.fetch("https://api.test/queue");
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");
    const { languages, release } = (await response.json()) as QueueBody;

    expect(Object.keys(languages)).toEqual(["uk", "ru", "es", "de"]);
    const zero = Object.fromEntries(STATES.map((s) => [s, 0]));
    expect(languages.uk).toMatchObject({ ...zero, enabled: true, paused: false, pausedReason: null, downSince: null, published: 2, publishedLast24h: 2, oldestWaitingAgeMinutes: null });
    expect(languages.ru).toMatchObject({ ...zero, enabled: true, published: 1, retrying: 1, publishedLast24h: 1, oldestWaitingAgeMinutes: 0, downSince: stored(now) });
    expect(languages.es).toMatchObject({ ...zero, paused: true, pausedReason: "manual", queued: 2, publishedLast24h: 0, lastPublishedAt: null, oldestWaitingAgeMinutes: 90 });
    expect(languages.de).toMatchObject({ ...zero, enabled: false, paused: false });
    expect(languages.uk.lastPublishedAt).toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
    // a2 waits for its Russian; summarized two hours ago (insertNews stamps the publication time).
    expect(release).toEqual({ waiting: 1, oldestWaitingAgeMinutes: 120 });
    // Nothing secret: only counts, times and the switches.
    expect(JSON.stringify(languages)).not.toMatch(/key|groq|zai|Bearer/i);
  });

  it("reads a few rows through indexes, however many translations were published before", async () => {
    const publishedRows = (from: number, n: number, at: string) =>
      env.DB.batch(
        Array.from({ length: n }, (_, i) =>
          env.DB.prepare(
            `INSERT INTO article_translations (article_id, lang, headline, short_summary, summary, model, source_summarized_at,
                                               lang_seq, translated_at, published_at, state, state_at)
             VALUES (?1, 'uk', 'Заголовок', 'Коротко.', 'Підсумок.', 'groq:x', ?2, ?3, ?2, ?2, 'published', ?2)`,
          ).bind(`p-${from + i}`, at, from + i + 1),
        ),
      );
    const articles = (from: number, n: number) =>
      env.DB.batch(
        Array.from({ length: n }, (_, i) =>
          env.DB.prepare(
            "INSERT INTO articles (id, source_id, url, original_title, published_at, fetched_at) VALUES (?1, 'de-federal-government', ?2, 'x', ?3, ?3)",
          ).bind(`p-${from + i}`, `https://example.gov/p-${from + i}`, hoursAgo(72)),
        ),
      );
    await articles(0, 40);
    await publishedRows(0, 40, hoursAgo(48));
    const at40 = await rowsRead(() => get("/queue"));
    await articles(40, 40);
    await publishedRows(40, 40, hoursAgo(48));
    const at80 = await rowsRead(() => get("/queue"));
    expect(at80).toBe(at40);
    expect(at40).toBeLessThanOrEqual(40);
    const body = (await get("/queue")).body as QueueBody;
    expect(body.languages.uk).toMatchObject({ published: 80, publishedLast24h: 0 });

    const { results } = await env.DB.prepare(
      `EXPLAIN QUERY PLAN SELECT (SELECT MIN(w.queued_at) FROM article_translations w INDEXED BY article_translations_waiting
                                  WHERE w.lang = 'uk' AND w.queued_at IS NOT NULL),
                                 (SELECT COUNT(*) FROM article_translations d INDEXED BY article_translations_published
                                  WHERE d.lang = 'uk' AND d.published_at >= ?)`,
    )
      .bind(hoursAgo(24))
      .all<{ detail: string }>();
    const plan = results.map((r) => r.detail).join("; ");
    expect(plan).toContain("SEARCH w USING COVERING INDEX article_translations_waiting (lang=?");
    expect(plan).toContain("SEARCH d USING COVERING INDEX article_translations_published (lang=? AND published_at>?)");
  });

  it("answers only GET", async () => {
    const response = await exports.default.fetch("https://api.test/queue", { method: "POST" });
    expect(response.status).toBe(405);
  });
});

describe("the four languages", () => {
  it("serve their own feeds and refuse an unknown one", async () => {
    await setLang("de", "enabled", 1);
    await insertNews("a1", hoursAgo(1));
    await run(fakeApis().fetch);
    for (const lang of LANGS) {
      const page = (await get(`/articles?lang=${lang}`)).body as ArticlesPage;
      expect(page.items.map((a) => [a.id, a.lang, a.headline])).toEqual([["a1", lang, TRANSLATED[lang].headline]]);
    }
    expect((await get("/articles?lang=pl")).status).toBe(400);
    expect(JSON.parse(answer("es")).headline).toBe(TRANSLATED.es.headline);
  });
});

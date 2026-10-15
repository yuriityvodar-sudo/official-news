// What the statements of scripts/queue.mjs do, run against the real schema (#46).
import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import * as sql from "../scripts/queue-sql.mjs";
import { LANGS, NOT_STORED, STATES, TRANSLATIONS_PER_RUN, runTranslator } from "../src/translator";
import {
  GLM_45,
  GPT_OSS_20B,
  QWEN,
  TRANSLATED,
  events,
  fakeApis,
  get,
  hideSeed,
  hoursAgo,
  ids,
  inMinutes,
  insertNews,
  minutesAgo,
  only,
  outcome,
  testEnv,
  translation,
} from "./helpers";

/** Runs a command's statements as wrangler d1 execute does: in one batch. */
const exec = async (statements: string[]) => env.DB.batch(statements.map((s) => env.DB.prepare(s)));
/** The rows a command changed: each write returns them (D1's `changes` also counts what the triggers write). */
const changes = (results: D1Result[]) => results.reduce((n, r) => n + r.results.length, 0);
const run = () => runTranslator(testEnv(), { maxTranslations: TRANSLATIONS_PER_RUN, fetch: fakeApis().fetch });
const langRow = (lang: string) => env.DB.prepare("SELECT enabled, paused FROM translation_langs WHERE lang = ?").bind(lang).first();

beforeEach(async () => {
  await hideSeed();
  // All four languages, so every command meets Groq and Z.ai (German is off by default).
  await only("uk", "ru", "es", "de");
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("scripts/queue.mjs", () => {
  it("knows the same languages and states as the Worker", () => {
    expect(sql.LANGS).toEqual([...LANGS]);
    expect(sql.STATES).toEqual([...STATES]);
  });

  it("status and list show each language's counts and its translations by state", async () => {
    await insertNews("a1", hoursAgo(1));
    await run();
    const [status] = await exec(sql.status());
    expect(status.results).toContainEqual(expect.objectContaining({ lang: "es", enabled: 1, paused: 0, state: "published", n: 1 }));
    const [list] = await exec(sql.list({ state: "published", lang: "de" }));
    expect(list.results).toEqual([expect.objectContaining({ article_id: "a1", lang: "de", state: "published", attempts: 0 })]);
    const [history] = await exec(sql.history("a1", "es"));
    expect((history.results as { state: string }[]).map((r) => r.state)).toEqual(["queued", "translating", "published"]);
  });

  it("requeue takes a failed translation back with fresh tries, and a published one to redo with its text shown", async () => {
    await insertNews("a1", hoursAgo(1));
    await run();
    await env.DB.prepare("UPDATE article_translations SET state = 'failed', attempts = 3, queued_at = NULL WHERE article_id = 'a1' AND lang = 'es'").run();

    expect(changes(await exec(sql.requeue("a1", "es")))).toBe(1);
    expect(await translation("a1", "es")).toMatchObject({ state: "updating", attempts: 0, last_error: "requeued by hand" });
    expect(changes(await exec(sql.requeue("nope", "es")))).toBe(0);
    expect(outcome(await run())).toEqual([`a1 es ${GPT_OSS_20B}`]);
    expect((await events("a1", "es")).map((e) => `${e.state} ${e.detail ?? ""}`.trim())).toContain("updating requeued by hand");
  });

  it("requeue-lang redoes a whole language, or only its failed ones", async () => {
    await insertNews("a1", hoursAgo(2));
    await insertNews("a2", hoursAgo(1));
    await run();
    await run();
    await env.DB.prepare("UPDATE article_translations SET state = 'failed' WHERE article_id = 'a2' AND lang = 'de'").run();

    expect(changes(await exec(sql.requeueLang("de", { failed: true })))).toBe(1);
    expect(await translation("a1", "de")).toMatchObject({ state: "published" });
    expect(changes(await exec(sql.requeueLang("uk")))).toBe(2);
    for (const id of ["a1", "a2"]) expect(await translation(id, "uk")).toMatchObject({ state: "updating", attempts: 0 });
  });

  it("requeue-lang keeps a published translation shown when its redo fails: it still matches the English", async () => {
    await insertNews("a1", hoursAgo(1));
    await run();
    expect(changes(await exec(sql.requeueLang("uk")))).toBe(1);

    // The redo gets three unusable answers (for example after a stricter prompt).
    for (const minutes of [0, 11, 32]) {
      await runTranslator(testEnv(), { maxTranslations: TRANSLATIONS_PER_RUN, fetch: fakeApis({ [QWEN]: ["not json"] }).fetch, now: inMinutes(minutes) });
    }

    const row = await translation("a1", "uk");
    expect(row).toMatchObject({ state: "failed", attempts: 3, headline: TRANSLATED.uk.headline });
    expect(row?.source_summarized_at).toBe(row?.attempts_source);
    expect(await ids("/articles?lang=uk")).toEqual(["a1"]);
    expect((await get("/articles/a1?lang=uk")).body).toMatchObject({ lang: "uk", headline: TRANSLATED.uk.headline });
  });

  it("a requeue made while a run translates that row is not undone when the run stores its answer", async () => {
    await insertNews("a1", hoursAgo(1));
    const apis = fakeApis();
    let requeued = false;
    const requeueMeanwhile = (async (input: RequestInfo | URL, init?: RequestInit) => {
      if (!requeued) {
        requeued = true;
        // The first request is Ukrainian: while it is on its way, someone requeues it (a new prompt is deployed).
        await exec(sql.requeue("a1", "uk"));
      }
      return apis.fetch(input, init);
    }) as typeof globalThis.fetch;

    const results = await runTranslator(testEnv(), { maxTranslations: TRANSLATIONS_PER_RUN, fetch: requeueMeanwhile });

    expect(results.find((r) => r.lang === "uk")).toMatchObject({ ok: false, error: NOT_STORED });
    expect(await translation("a1", "uk")).toMatchObject({ state: "queued", headline: null, last_error: "requeued by hand" });
    // The next run makes it again, as the requeue asked; only that run's answer is published.
    expect(outcome(await run())).toEqual([`a1 uk ${QWEN}`]);
    expect((await events("a1", "uk")).map((e) => e.state)).toEqual(["queued", "translating", "queued", "translating", "published"]);
  });

  it("pause and resume, disable and enable: enable queues the feed's 7 days the language missed", async () => {
    await exec(sql.disable("de"));
    await insertNews("a1", hoursAgo(30));
    await run();
    // Enabling queues the feed's 7 days at once (the next run would also queue them, since German has nothing queued).
    await exec(sql.enable("de"));
    expect(await langRow("de")).toEqual({ enabled: 1, paused: 0 });
    expect(await translation("a1", "de")).toMatchObject({ state: "queued" });

    await exec(sql.pause("de"));
    expect(await langRow("de")).toEqual({ enabled: 1, paused: 1 });
    expect((await run()).filter((r) => r.lang === "de")).toEqual([]);
    await exec(sql.resume("de"));
    expect(outcome(await run())).toEqual([`a1 de ${GLM_45}`]);
  });

  it("pause is manual and stays; resume also ends an automatic pause, with a fresh start", async () => {
    const reason = () =>
      env.DB.prepare("SELECT paused, paused_reason, down_since FROM translation_langs WHERE lang = 'es'").first();
    const [paused] = await exec(sql.pause("es"));
    expect(paused.results).toEqual([expect.objectContaining({ lang: "es", paused: 1, paused_reason: "manual" })]);
    const [status] = await exec(sql.status());
    expect(status.results).toContainEqual(expect.objectContaining({ lang: "es", paused: 1, paused_reason: "manual", down_since: null }));
    // A provider's answer ends only an automatic pause: a manual one is never probed.
    await insertNews("a1", hoursAgo(1));
    expect((await run()).filter((r) => r.lang === "es")).toEqual([]);
    expect(await reason()).toEqual({ paused: 1, paused_reason: "manual", down_since: null });

    await env.DB.prepare(
      "UPDATE translation_langs SET paused_reason = 'auto: provider down since 2026-10-15T08:00:00Z', down_since = '2026-10-15T08:00:00Z' WHERE lang = 'es'",
    ).run();
    await exec(sql.resume("es"));
    expect(await reason()).toEqual({ paused: 0, paused_reason: null, down_since: null });
  });

  it("backlog queues only what is not queued yet for its English, within the feed's 7 days", async () => {
    await insertNews("a1", hoursAgo(2));
    await insertNews("old", hoursAgo(8 * 24));
    await run();
    await env.DB.prepare("DELETE FROM article_translations WHERE lang = 'ru'").run();
    expect(changes(await exec(sql.backlog("ru")))).toBe(1);
    expect(changes(await exec(sql.backlog("ru")))).toBe(0);
    expect(changes(await exec(sql.backlog("uk")))).toBe(0);
    expect(await translation("old", "ru")).toBeNull();
    expect(minutesAgo(0) >= String((await translation("a1", "ru"))?.queued_at)).toBe(true);
  });

  it("quotes what it puts into SQL, and refuses what it does not know", () => {
    expect(() => sql.requeue("x'; DROP TABLE articles; --", "uk")).toThrow(/article id/);
    expect(() => sql.pause("pl")).toThrow(/language must be one of/);
    expect(() => sql.list({ state: "done" })).toThrow(/state must be one of/);
  });
});

// Push notifications (#62, Yurii 16 Oct): breaking decisions (importance 4+)
// released in the last 24 hours, at most 2 a local day per language and at
// least 1 (the day's top story at 18:00), 3 hours apart, never 21:00 to 08:00
// in the language's main time zone. Google's token endpoint and FCM are fakes;
// the service account's key is made for each test run and never stored.
import { createScheduledController } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import worker, { CRONS } from "../src/index";
import {
  BODY_MAX,
  BREAKING_CANDIDATE,
  CLAIM_PUSH,
  PUSH_STATE,
  type PushLang,
  TIME_ZONES,
  TOP_CANDIDATE,
  localClock,
  runPush,
  shorten,
} from "../src/push";
import { FCM_SCOPE, PAUSE_MINUTES, TOKEN_MARGIN_MS, TOKEN_URL, fcmUrl, retryLater } from "../src/push/fcm";
import type { Lang } from "../src/translator";
import { d1Rows, hideSeed, insertNews, only, stored, testEnv } from "./helpers";

const PROJECT = "official-news-48e16";
const EMAIL = `fcm-sender@${PROJECT}.iam.gserviceaccount.com`;

/** A time on 16 Oct 2026 (or `day`) given in London's local time (BST, UTC+1 until 25 Oct). */
const london = (hour: number, minute = 0, day = 16) => new Date(Date.UTC(2026, 9, day, hour - 1, minute));
/** The same in Kyiv's local time (EEST, UTC+3). */
const kyiv = (hour: number, minute = 0, day = 16) => new Date(Date.UTC(2026, 9, day, hour - 3, minute));
const later = (date: Date, minutes: number) => new Date(date.getTime() + minutes * 60_000);

let serviceAccount: string;
let publicKey: CryptoKey;

/** A real RSA key pair, as in a service account's JSON key file, made for this test run only. */
beforeAll(async () => {
  const pair = (await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
  publicKey = pair.publicKey;
  const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  let binary = "";
  for (const byte of der) binary += String.fromCharCode(byte);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(binary).match(/.{1,64}/g)!.join("\n")}\n-----END PRIVATE KEY-----\n`;
  serviceAccount = JSON.stringify({ type: "service_account", project_id: PROJECT, client_email: EMAIL, private_key: pem });
});

beforeEach(async () => {
  await hideSeed();
  // English only, unless a test turns a language on.
  await only();
});

afterEach(() => {
  vi.restoreAllMocks();
});

/** The Worker's env with the test service account as FCM_SERVICE_ACCOUNT, another secret, or none (null). */
const pushEnv = (secret: string | null = serviceAccount) => ({ ...env, FCM_SERVICE_ACCOUNT: secret ?? undefined });

/** A released decision: in the feed since `addedAt`, with the next feed_seq. Insert them oldest first. */
async function decision(id: string, importance: number | null, addedAt: Date, { shortSummary = `Short summary of ${id}.`, publishedAt = addedAt } = {}) {
  await env.DB.prepare(
    `INSERT INTO articles (id, source_id, url, original_title, published_at, fetched_at, headline, short_summary, summary,
                           is_news, importance, decision_type, summarized_at, topics, tags, feed_seq, added_at)
     VALUES (?1, 'de-federal-government', 'https://example.gov/' || ?1, 'Original ' || ?1, ?2, ?2, 'Headline ' || ?1, ?3,
             'Summary.', 1, ?4, 'decision', ?2, '[]', '[]',
             (SELECT COALESCE(MAX(feed_seq), 0) + 1 FROM articles WHERE feed_seq IS NOT NULL), ?5)`,
  )
    .bind(id, stored(publishedAt), shortSummary, importance, stored(addedAt))
    .run();
}

/** The article's translation into `lang`, in `state` (published: the translation of the current English). */
const translated = (id: string, lang: Lang, state = "published") =>
  env.DB.prepare(
    `INSERT INTO article_translations (article_id, lang, headline, short_summary, summary, model, source_summarized_at,
                                       attempts_source, lang_seq, translated_at, published_at, state, state_at)
     SELECT id, ?2, 'Заголовок ' || id, 'Коротко про ' || id || '.', 'Підсумок.', 'groq:x', summarized_at, summarized_at,
            (SELECT COALESCE(MAX(lang_seq), 0) + 1 FROM article_translations WHERE lang = ?2), summarized_at, summarized_at, ?3, summarized_at
     FROM articles WHERE id = ?1`,
  )
    .bind(id, lang, state)
    .run();

/** A translation that used its 3 tries: no text. */
const failed = (id: string, lang: Lang) =>
  env.DB.prepare(
    `INSERT INTO article_translations (article_id, lang, attempts_source, attempts, state, state_at)
     SELECT id, ?2, summarized_at, 3, 'failed', summarized_at FROM articles WHERE id = ?1`,
  )
    .bind(id, lang)
    .run();

type Reply = { status: number; body?: unknown; headers?: Record<string, string> } | Error;

interface Sent {
  url: string;
  authorization: string | null;
  body: { message: { topic: string; notification: { title: string; body: string }; data: { articleId: string; lang: string } } };
  /** Whether push_log held the claim (no message id, no error) when the request was made. */
  claimedFirst: boolean;
}

/**
 * A fake Google: the token endpoint answers `token-1`, `token-2` … (valid 3599
 * s) after checking the JWT's signature with the test key, and FCM accepts
 * every message (`projects/…/messages/1`, 2 …) unless `fcm` lists a reply for
 * the next one.
 */
function fakeGoogle({ fcm = [] as Reply[], token = [] as Reply[] } = {}) {
  const tokenRequests: { form: URLSearchParams; header: Record<string, unknown>; claims: Record<string, unknown>; valid: boolean }[] = [];
  const messages: Sent[] = [];
  const decode = (part: string) => Uint8Array.from(atob(part.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
  const json = (part: string) => JSON.parse(new TextDecoder().decode(decode(part))) as Record<string, unknown>;
  const answer = (reply: Reply) => {
    if (reply instanceof Error) throw reply;
    return new Response(JSON.stringify(reply.body ?? {}), { status: reply.status, headers: { "content-type": "application/json", ...reply.headers } });
  };
  const fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    if (url === TOKEN_URL) {
      const form = new URLSearchParams(String(init?.body));
      const [header, claims, signature] = (form.get("assertion") ?? "").split(".");
      const valid = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", publicKey, decode(signature), new TextEncoder().encode(`${header}.${claims}`));
      tokenRequests.push({ form, header: json(header), claims: json(claims), valid });
      return answer(token.shift() ?? { status: 200, body: { access_token: `token-${tokenRequests.length}`, expires_in: 3599, token_type: "Bearer" } });
    }
    if (url === fcmUrl(PROJECT)) {
      const body = JSON.parse(String(init?.body)) as Sent["body"];
      const { articleId, lang } = body.message.data;
      const row = await env.DB.prepare("SELECT message_id, error FROM push_log WHERE article_id = ? AND lang = ?").bind(articleId, lang).first();
      messages.push({ url, authorization: new Headers(init?.headers).get("authorization"), body, claimedFirst: !!row && row.message_id === null && row.error === null });
      return answer(fcm.shift() ?? { status: 200, body: { name: `projects/${PROJECT}/messages/${messages.length}` } });
    }
    throw new Error(`unexpected request to ${url}`);
  }) as typeof globalThis.fetch;
  return { fetch, tokenRequests, messages };
}

type Google = ReturnType<typeof fakeGoogle>;
const push = (now: Date, google: Google, e = pushEnv()) => runPush(e, { now, fetch: google.fetch });
/** What a run sent, as "lang article kind" (or "lang article failed: why"). */
const sent = (run: Awaited<ReturnType<typeof runPush>>) =>
  run.pushes.map((p) => `${p.lang} ${p.articleId} ${p.ok ? p.kind : `failed: ${p.error}`}`);
const pushLog = async () =>
  (await env.DB.prepare("SELECT * FROM push_log ORDER BY sent_at, lang").all<Record<string, unknown>>()).results;
const quiet = () => vi.spyOn(console, "log").mockImplementation(() => {});

describe("push notifications", () => {
  it("sends a released importance 4+ decision to its language's topic: the headline, the short summary, the article to open", async () => {
    await decision("a1", 4, london(10, 30));
    const google = fakeGoogle();
    const log = quiet();
    const now = london(11);
    const run = await push(now, google);

    expect(run.pushes).toEqual([{ lang: "en", articleId: "a1", kind: "breaking", ok: true, messageId: `projects/${PROJECT}/messages/1` }]);
    expect(google.messages).toEqual([
      {
        url: `https://fcm.googleapis.com/v1/projects/${PROJECT}/messages:send`,
        authorization: "Bearer token-1",
        body: {
          message: {
            topic: "breaking_en",
            notification: { title: "Headline a1", body: "Short summary of a1." },
            data: { articleId: "a1", lang: "en" },
            apns: { payload: { aps: { sound: "default" } } },
          },
        },
        // Written to push_log before the request, so a run cut off never sends it again.
        claimedFirst: true,
      },
    ]);
    expect(await pushLog()).toEqual([
      { article_id: "a1", lang: "en", sent_at: stored(now), topic: "breaking_en", message_id: `projects/${PROJECT}/messages/1`, error: null, refused: 0 },
    ]);
    const lines = log.mock.calls.map((c) => JSON.parse(String(c[0])));
    expect(lines).toHaveLength(1);
    expect(lines[0]).toMatchObject({ message: "push run", pushes: run.pushes, skipped: { uk: "language off", ru: "language off", es: "language off", de: "language off" } });
  });

  it("gets its access token with a JWT signed by the service account's key, for FCM only", async () => {
    await decision("a1", 5, london(10));
    const google = fakeGoogle();
    quiet();
    const now = london(11);
    await push(now, google);

    expect(google.tokenRequests).toHaveLength(1);
    const [request] = google.tokenRequests;
    expect(request.form.get("grant_type")).toBe("urn:ietf:params:oauth:grant-type:jwt-bearer");
    expect(request.valid).toBe(true);
    expect(request.header).toEqual({ alg: "RS256", typ: "JWT" });
    const iat = now.getTime() / 1000;
    expect(request.claims).toEqual({ iss: EMAIL, scope: FCM_SCOPE, aud: TOKEN_URL, iat, exp: iat + 3600 });
  });

  it("pushes importance 4 and 5 only outside the daily slot, the most important first, then the newest", async () => {
    await decision("a1", 3, london(9));
    await decision("a2", 4, london(9, 10));
    await decision("a3", 5, london(9, 20));
    await decision("a4", 5, london(9, 30));
    await decision("a5", null, london(9, 40));
    const google = fakeGoogle();
    quiet();
    expect(sent(await push(london(10), google))).toEqual(["en a4 breaking"]);
    expect(sent(await push(london(13), google))).toEqual(["en a3 breaking"]);

    // Only importance 3 and below left (a2 waits for a day with room): nothing before the slot.
    await env.DB.prepare("DELETE FROM push_log").run();
    await env.DB.prepare("UPDATE articles SET importance = 3 WHERE id IN ('a2', 'a3', 'a4')").run();
    const run = await push(london(16), google);
    expect(run.pushes).toEqual([]);
    expect(run.skipped.en).toBe("nothing breaking (importance 4+) in the last 24 hours");
  });

  it("never pushes an article twice in a language, also one a run claimed and did not finish", async () => {
    await decision("a1", 5, london(9));
    await decision("a2", 5, london(9, 5));
    // A run that was cut off after claiming a2: no message id, no error.
    await env.DB.prepare("INSERT INTO push_log (article_id, lang, sent_at, topic) VALUES ('a2', 'en', ?, 'breaking_en')").bind(stored(london(8))).run();
    const google = fakeGoogle();
    quiet();
    expect(sent(await push(london(11), google))).toEqual(["en a1 breaking"]);
    // a1 and a2 are done in English: nothing else qualifies, and the cap counts the claim too.
    const run = await push(london(16), google);
    expect(run.pushes).toEqual([]);
    expect(run.skipped.en).toBe("daily cap (2 today)");
    expect(google.messages.map((m) => m.body.message.data.articleId)).toEqual(["a1"]);
  });

  it("sends at most 2 a local day per language; the count starts again at local midnight", async () => {
    await decision("a1", 4, london(10));
    await decision("a2", 4, london(10, 1));
    await decision("a3", 4, london(10, 2));
    const google = fakeGoogle();
    quiet();
    expect(sent(await push(london(10, 30), google))).toEqual(["en a3 breaking"]);
    expect(sent(await push(london(13, 30), google))).toEqual(["en a2 breaking"]);
    for (const now of [london(16, 30), london(20, 59)]) {
      const run = await push(now, google);
      expect(run.pushes).toEqual([]);
      expect(run.skipped.en).toBe("daily cap (2 today)");
    }
    // The next morning, a1 is still less than 24 hours old.
    expect(sent(await push(london(8, 30, 17), google))).toEqual(["en a1 breaking"]);
  });

  it("leaves at least 3 hours between two pushes in the same language", async () => {
    await decision("a1", 4, london(10));
    const google = fakeGoogle();
    quiet();
    expect(sent(await push(london(10, 5), google))).toEqual(["en a1 breaking"]);
    await decision("a2", 5, london(11));
    const early = await push(london(13, 4), google);
    expect(early.pushes).toEqual([]);
    expect(early.skipped.en).toBe(`spacing (last push ${stored(london(10, 5))})`);
    expect(sent(await push(london(13, 5), google))).toEqual(["en a2 breaking"]);
  });

  it("sends nothing from 21:00 to 08:00 in each language's time zone, and the night's decision in the morning", async () => {
    await only("uk");
    // 22:00 in Kyiv, 20:00 in London.
    await decision("a1", 5, kyiv(22));
    await translated("a1", "uk");
    const google = fakeGoogle();
    quiet();
    const night = await push(kyiv(22, 30), google);
    expect(sent(night)).toEqual(["en a1 breaking"]);
    expect(night.skipped.uk).toBe("quiet hours (22:30 in Europe/Kyiv)");

    // 07:59 in Kyiv (05:59 in London): every language is quiet, so the run reads nothing at all.
    let run: Awaited<ReturnType<typeof runPush>> | undefined;
    const rows = await d1Rows(async () => (run = await push(kyiv(7, 59, 17), google)));
    expect(rows).toEqual({ read: 0, written: 0 });
    expect(run?.skipped).toMatchObject({ en: "quiet hours (05:59 in Europe/London)", uk: "quiet hours (07:59 in Europe/Kyiv)" });

    const morning = await push(kyiv(8, 0, 17), google);
    expect(sent(morning)).toEqual(["uk a1 breaking"]);
    expect(morning.skipped.en).toBe("quiet hours (06:00 in Europe/London)");
  });

  it("sends the day's top story at 18:00 local when nothing went out that day", async () => {
    await decision("a1", 2, london(9));
    await decision("a2", 3, london(10));
    await decision("a3", 3, london(11));
    await decision("a4", 1, london(12));
    const google = fakeGoogle();
    quiet();
    const before = await push(london(17, 59), google);
    expect(before.pushes).toEqual([]);
    expect(before.skipped.en).toBe("nothing breaking (importance 4+) in the last 24 hours");
    // The highest importance, then the newest: a3.
    expect(sent(await push(london(18), google))).toEqual(["en a3 daily"]);
    expect(google.messages[0].body.message).toMatchObject({ topic: "breaking_en", data: { articleId: "a3", lang: "en" } });
  });

  it("sends no top story at the daily slot when a push already went out that day", async () => {
    await decision("b1", 4, london(11));
    const google = fakeGoogle();
    quiet();
    expect(sent(await push(london(12), google))).toEqual(["en b1 breaking"]);
    await decision("b2", 2, london(13));
    const slot = await push(london(18, 30), google);
    expect(slot.pushes).toEqual([]);
    expect(slot.skipped.en).toBe("nothing breaking (importance 4+) in the last 24 hours");
  });

  it("pushes in another language only when its translation is published, with the translated text", async () => {
    await only("uk", "ru");
    await decision("a1", 5, london(9));
    await translated("a1", "uk");
    await failed("a1", "ru");
    await decision("a2", 4, london(9, 30));
    // An older translation shown while the new English waits: not the current English, so no push.
    await translated("a2", "uk", "updating");
    await translated("a2", "ru");
    const google = fakeGoogle();
    quiet();
    const run = await push(london(11), google);
    expect(sent(run)).toEqual(["en a1 breaking", "uk a1 breaking", "ru a2 breaking"]);
    expect(run.skipped).toEqual({ es: "language off", de: "language off" });
    const uk = google.messages.find((m) => m.body.message.topic === "breaking_uk");
    expect(uk?.body.message).toMatchObject({ notification: { title: "Заголовок a1", body: "Коротко про a1." }, data: { articleId: "a1", lang: "uk" } });
    expect(google.messages.find((m) => m.body.message.topic === "breaking_ru")?.body.message.data).toEqual({ articleId: "a2", lang: "ru" });
    // One token for the whole run.
    expect(google.tokenRequests).toHaveLength(1);

    const next = await push(london(14), google);
    expect(sent(next)).toEqual(["en a2 breaking"]);
    expect(next.skipped).toMatchObject({
      uk: "nothing breaking (importance 4+) in the last 24 hours",
      ru: "nothing breaking (importance 4+) in the last 24 hours",
    });
  });

  it("pushes only decisions released in the last 24 hours that are in the feed", async () => {
    // Released 25 hours ago; released now but published 8 days ago (shown nowhere); hidden after its release.
    await decision("old", 5, london(10, 0, 15));
    await decision("past", 5, london(10), { publishedAt: london(10, 0, 8) });
    await decision("hidden", 5, london(10, 30));
    await env.DB.prepare("UPDATE articles SET is_news = 0 WHERE id = 'hidden'").run();
    const google = fakeGoogle();
    quiet();
    const run = await push(london(11), google);
    expect(run.pushes).toEqual([]);
    expect(google.tokenRequests).toEqual([]);
  });

  it("cuts the body to about 110 characters at the end of a word, with an ellipsis", async () => {
    expect(shorten("The cabinet approved the budget.")).toBe("The cabinet approved the budget.");
    expect(shorten("  Two\nlines  ")).toBe("Two lines");
    const long =
      "The federal cabinet approved the draft budget for 2027, which raises spending on defence, schools and railways by four percent.";
    const cut = shorten(long);
    expect(cut).toBe("The federal cabinet approved the draft budget for 2027, which raises spending on defence, schools and…");
    expect([...cut].length).toBeLessThanOrEqual(BODY_MAX);
    // A word that ends exactly at the limit stays whole; no comma before the ellipsis.
    expect(shorten("aaaa bbbb, cccc", 11)).toBe("aaaa bbbb…");
    expect(shorten("aaaa bbbbbb cccc", 12)).toBe("aaaa bbbbbb…");
    // Cyrillic is cut by letters, at a word too.
    const ukrainian = "Кабінет міністрів схвалив проєкт державного бюджету на 2027 рік, який збільшує видатки на оборону, школи та залізниці.";
    const ukCut = shorten(ukrainian);
    expect([...ukCut].length).toBeLessThanOrEqual(BODY_MAX);
    expect(ukCut.endsWith("…")).toBe(true);
    expect(ukrainian.startsWith(ukCut.slice(0, -1))).toBe(true);
    expect(ukrainian[ukCut.length - 1]).toBe(" ");

    await decision("a1", 4, london(10), { shortSummary: long });
    const google = fakeGoogle();
    quiet();
    await push(london(11), google);
    expect(google.messages[0].body.message.notification.body).toBe(cut);
  });

  it("keeps the access token in D1 and uses it until 5 minutes before it expires", async () => {
    await only("uk", "ru");
    await decision("a1", 5, london(9));
    const google = fakeGoogle();
    quiet();
    const t0 = london(10);
    expect(sent(await push(t0, google))).toEqual(["en a1 breaking"]);
    // Valid 3599 seconds: kept until 5 minutes before that.
    const expiresAt = new Date(t0.getTime() + 3599_000 - TOKEN_MARGIN_MS);
    expect(await env.DB.prepare("SELECT key, value, expires_at FROM kv_cache").all().then((r) => r.results)).toEqual([
      { key: `fcm_token:${EMAIL}`, value: "token-1", expires_at: stored(expiresAt) },
    ]);

    // Ukrainian is published half an hour later: the next run sends it with the same token, without asking Google.
    await translated("a1", "uk");
    expect(sent(await push(later(t0, 30), google))).toEqual(["uk a1 breaking"]);
    expect(google.tokenRequests).toHaveLength(1);

    // Russian after the token's time in the cache: a new token.
    await translated("a1", "ru");
    expect(sent(await push(expiresAt, google))).toEqual(["ru a1 breaking"]);
    expect(google.tokenRequests).toHaveLength(2);
    expect(google.messages.map((m) => m.authorization)).toEqual(["Bearer token-1", "Bearer token-1", "Bearer token-2"]);
  });

  it("records an FCM refusal in push_log and never tries that article again", async () => {
    await decision("a1", 5, london(9));
    await decision("a2", 4, london(9, 30));
    const google = fakeGoogle({ fcm: [{ status: 400, body: { error: { code: 400, status: "INVALID_ARGUMENT", message: "Invalid value" } } }] });
    const log = quiet();
    const first = await push(london(10), google);
    expect(sent(first)).toEqual(["en a1 failed: HTTP 400 INVALID_ARGUMENT: Invalid value"]);
    expect(first.pushes[0].outcome).toBe("refused");
    expect(await pushLog()).toEqual([
      { article_id: "a1", lang: "en", sent_at: stored(london(10)), topic: "breaking_en", message_id: null, error: "HTTP 400 INVALID_ARGUMENT: Invalid value", refused: 1 },
    ]);
    expect(JSON.parse(String(log.mock.calls[0][0])).pushes).toEqual(first.pushes);

    // It counts for the spacing, so messages FCM keeps refusing cost one try in 3 hours, never the same article twice.
    expect((await push(london(11), google)).skipped.en).toBe(`spacing (last push ${stored(london(10))})`);
    expect(sent(await push(london(13), google))).toEqual(["en a2 breaking"]);
    // Not for the daily cap: a2 was today's first push that went out.
    await decision("a3", 4, london(15));
    expect(sent(await push(london(16), google))).toEqual(["en a3 breaking"]);
    expect(google.messages.map((m) => m.body.message.data.articleId)).toEqual(["a1", "a2", "a3"]);
    // Only an answer about the token, the permission, the quota or FCM itself is tried again.
    expect([400, 401, 403, 404, 408, 413, 429, 500, 503].filter(retryLater)).toEqual([401, 403, 408, 429, 500, 503]);
  });

  it("counts a request without an answer (the timeout, a network error) as sent: never tried again, and in the daily cap", async () => {
    await decision("a1", 5, london(7, 30));
    await decision("a2", 4, london(7, 40));
    await decision("a3", 4, london(7, 50));
    // FCM may have taken a1 before the 10 s timeout: readers may have it.
    const timeout = Object.assign(new Error("The operation was aborted due to timeout"), { name: "TimeoutError" });
    const google = fakeGoogle({ fcm: [timeout] });
    quiet();
    const first = await push(london(8), google);
    expect(sent(first)).toEqual(["en a1 failed: request failed: The operation was aborted due to timeout"]);
    expect(first.pushes[0].outcome).toBe("unknown");
    expect(sent(await push(london(11), google))).toEqual(["en a3 breaking"]);
    const third = await push(london(14), google);
    expect(third.pushes).toEqual([]);
    expect(third.skipped.en).toBe("daily cap (2 today)");
    // At most 2 requests to the topic in the local day.
    expect(google.messages.map((m) => m.body.message.data.articleId)).toEqual(["a1", "a3"]);
    expect((await pushLog()).map((r) => [r.article_id, r.message_id, r.error, r.refused])).toEqual([
      ["a1", null, "request failed: The operation was aborted due to timeout", 0],
      ["a3", `projects/${PROJECT}/messages/2`, null, 0],
    ]);
  });

  it("stops at a token FCM refuses (401): gives back every claim not sent, forgets the token, and sends them after the pause", async () => {
    await only("uk", "ru");
    await decision("a1", 5, london(9));
    await translated("a1", "uk");
    await translated("a1", "ru");
    // A token cached before its own expiry that FCM no longer takes (its service account disabled, say).
    await env.DB.prepare("INSERT INTO kv_cache (key, value, expires_at) VALUES (?1, 'revoked', ?2)").bind(`fcm_token:${EMAIL}`, stored(london(10, 40))).run();
    const google = fakeGoogle({ fcm: [{ status: 401, body: { error: { status: "UNAUTHENTICATED", message: "Request had invalid authentication credentials." } } }] });
    quiet();
    const first = await push(london(10), google);
    expect(sent(first)).toEqual(["en a1 failed: HTTP 401 UNAUTHENTICATED: Request had invalid authentication credentials."]);
    expect(first.pushes[0].outcome).toBe("retry");
    const why = "FCM: HTTP 401 UNAUTHENTICATED: Request had invalid authentication credentials.";
    const until = stored(later(london(10), PAUSE_MINUTES));
    expect(first.skipped).toMatchObject({ uk: `paused until ${until} (${why})`, ru: `paused until ${until} (${why})` });
    // One request, not one per language; no claim kept; the token gone, the pause in its place.
    expect(google.messages.map((m) => m.authorization)).toEqual(["Bearer revoked"]);
    expect(await pushLog()).toEqual([]);
    expect((await env.DB.prepare("SELECT key, value, expires_at FROM kv_cache").all()).results).toEqual([
      { key: `fcm_pause:${EMAIL}`, value: why, expires_at: until },
    ]);

    // During the pause a run neither signs, nor asks Google, nor sends.
    const during = await push(london(10, 8), google);
    expect(during.skipped).toMatchObject({ en: `paused until ${until} (${why})`, uk: `paused until ${until} (${why})` });
    expect(google.tokenRequests).toHaveLength(0);
    // After it: a new token, and the article goes out in every language.
    expect(sent(await push(later(london(10), PAUSE_MINUTES), google))).toEqual(["en a1 breaking", "uk a1 breaking", "ru a1 breaking"]);
    expect(google.tokenRequests).toHaveLength(1);
    expect(google.messages.slice(1).map((m) => m.authorization)).toEqual(["Bearer token-1", "Bearer token-1", "Bearer token-1"]);
  });

  it("tries again when FCM could not take a message (503, 429): after the pause, or FCM's Retry-After when longer", async () => {
    // Nothing breaking that day, and FCM busy at the daily slot: the day's one push still goes out.
    await decision("a1", 3, london(9));
    await decision("a2", 2, london(10));
    await decision("a3", 3, london(11));
    const google = fakeGoogle({
      fcm: [
        { status: 503, body: { error: { status: "UNAVAILABLE", message: "The service is currently unavailable." } } },
        { status: 429, body: { error: { status: "RESOURCE_EXHAUSTED", message: "Quota exceeded." } }, headers: { "retry-after": "1800" } },
      ],
    });
    quiet();
    expect(sent(await push(london(18), google))).toEqual(["en a3 failed: HTTP 503 UNAVAILABLE: The service is currently unavailable."]);
    expect(await pushLog()).toEqual([]);
    expect((await push(london(18, 8), google)).skipped.en).toBe(
      `paused until ${stored(london(18, 10))} (FCM: HTTP 503 UNAVAILABLE: The service is currently unavailable.)`,
    );
    // Retry-After 30 minutes: longer than the pause, so honoured.
    expect(sent(await push(london(18, 10), google))).toEqual(["en a3 failed: HTTP 429 RESOURCE_EXHAUSTED: Quota exceeded."]);
    expect((await push(london(18, 30), google)).skipped.en).toBe(`paused until ${stored(london(18, 40))} (FCM: HTTP 429 RESOURCE_EXHAUSTED: Quota exceeded.)`);
    expect(sent(await push(london(18, 40), google))).toEqual(["en a3 daily"]);
    expect(google.messages).toHaveLength(3);
    expect(google.tokenRequests).toHaveLength(1);
  });

  it("claims nothing when Google gives no access token, and asks again only after the pause", async () => {
    await decision("a1", 5, london(9));
    const google = fakeGoogle({ token: [{ status: 400, body: { error: "invalid_grant", error_description: "Invalid JWT Signature." } }] });
    quiet();
    const why = "no access token: token request: HTTP 400 invalid_grant: Invalid JWT Signature.";
    const run = await push(london(10), google);
    expect(run.pushes).toEqual([]);
    expect(run.skipped.en).toBe(why);
    expect(await pushLog()).toEqual([]);
    expect(google.messages).toEqual([]);
    // The runs in between (every 2 minutes) neither sign a JWT nor ask Google.
    for (const minute of [2, 4, 6, 8]) {
      expect((await push(london(10, minute), google)).skipped.en).toBe(`paused until ${stored(london(10, 10))} (${why})`);
    }
    expect(google.tokenRequests).toHaveLength(1);
    // Then it asks again, and sends.
    expect(sent(await push(london(10, 10), google))).toEqual(["en a1 breaking"]);
    expect(google.tokenRequests).toHaveLength(2);
  });

  it("does nothing without FCM_SERVICE_ACCOUNT: no request, no database read, one log line", async () => {
    await decision("a1", 5, london(9));
    const google = fakeGoogle();
    const log = quiet();
    let run: Awaited<ReturnType<typeof runPush>> | undefined;
    const rows = await d1Rows(async () => (run = await push(london(10), google, pushEnv(null))));
    expect(run).toEqual({ pushes: [], skipped: {} });
    expect(rows).toEqual({ read: 0, written: 0 });
    expect(google.tokenRequests).toEqual([]);
    expect(google.messages).toEqual([]);
    expect(log.mock.calls.map((c) => JSON.parse(String(c[0])))).toEqual([{ message: "push skipped: FCM_SERVICE_ACCOUNT not set" }]);
  });

  it("does nothing with a secret that is not a service account key, and says what is missing, never a value", async () => {
    await decision("a1", 5, london(9));
    const google = fakeGoogle();
    const log = quiet();
    for (const secret of ["not json", JSON.stringify({ client_email: EMAIL, private_key: "x" })]) {
      expect((await push(london(10), google, pushEnv(secret))).pushes).toEqual([]);
    }
    expect(log.mock.calls.map((c) => JSON.parse(String(c[0])))).toEqual([
      { message: "push skipped", reason: "FCM_SERVICE_ACCOUNT is not JSON (it should be the service account's whole JSON key file)" },
      { message: "push skipped", reason: "FCM_SERVICE_ACCOUNT has no project_id" },
    ]);
    // A private_key that is not a key: no token, and the step pauses as for any token failure.
    const badKey = await push(london(10), google, pushEnv(JSON.stringify({ client_email: EMAIL, private_key: "not a key", project_id: PROJECT })));
    expect(badKey.skipped.en).toMatch(/^no access token: FCM_SERVICE_ACCOUNT's private_key (is not a PEM key|cannot be read: )/);
    expect(await env.DB.prepare("SELECT key FROM kv_cache").all().then((r) => r.results)).toEqual([{ key: `fcm_pause:${EMAIL}` }]);
    expect(google.tokenRequests).toEqual([]);
  });

  it("sends nothing twice when two runs overlap", async () => {
    await decision("a1", 5, london(9));
    await decision("a2", 5, london(9, 30));
    // The second run starts while the first waits for FCM, and finds a1 claimed and the language just pushed.
    let second: Promise<Awaited<ReturnType<typeof runPush>>> | undefined;
    const google = fakeGoogle();
    const overlapping = (async (input: RequestInfo | URL, init?: RequestInit) => {
      if (String(input) === fcmUrl(PROJECT) && !second) second = push(london(10, 1), google);
      return google.fetch(input, init);
    }) as typeof globalThis.fetch;
    quiet();
    const first = await runPush(pushEnv(), { now: london(10), fetch: overlapping });
    expect(sent(first)).toEqual(["en a2 breaking"]);
    expect((await second)?.pushes).toEqual([]);
    expect(google.messages).toHaveLength(1);
  });

  it("sends nothing twice when two runs read the state before either claims", async () => {
    await decision("a1", 5, london(9));
    await decision("a2", 5, london(9, 30));
    // The second run starts and finishes while the first waits for its token: both read
    // PUSH_STATE before either claimed, so only the claim keeps the first from sending.
    let started = false;
    let second: Awaited<ReturnType<typeof runPush>> | undefined;
    const google = fakeGoogle();
    const racing = (async (input: RequestInfo | URL, init?: RequestInit) => {
      if (String(input) === TOKEN_URL && !started) {
        started = true;
        second = await push(london(10, 1), google);
      }
      return google.fetch(input, init);
    }) as typeof globalThis.fetch;
    quiet();
    const first = await runPush(pushEnv(), { now: london(10), fetch: racing });
    expect(second && sent(second)).toEqual(["en a2 breaking"]);
    expect(first.pushes).toEqual([]);
    expect(first.skipped.en).toBe("claimed by another run");
    expect(google.messages).toHaveLength(1);
  });

  it("keeps a claim safe against another run: the cap, the spacing and the article are checked in the same statement", async () => {
    await decision("a1", 5, london(9));
    const claim = (article: string, now: Date) =>
      env.DB.prepare(CLAIM_PUSH)
        .bind(article, "en", stored(now), "breaking_en", stored(later(now, -180)), stored(london(0)), 2)
        .all()
        .then((r) => r.results.length);
    expect(await claim("a1", london(10))).toBe(1);
    expect(await claim("a1", london(14))).toBe(0); // pushed before
    expect(await claim("a2", london(12))).toBe(0); // within 3 hours
    expect(await claim("a2", london(13))).toBe(1);
    expect(await claim("a3", london(17))).toBe(0); // 2 today
  });

  it("knows each language's local time, also across a clock change", () => {
    const zones = Object.keys(TIME_ZONES) as PushLang[];
    expect(zones.sort()).toEqual(["de", "en", "es", "ru", "uk"]);
    // 12:00 UTC on 16 Oct: summer time everywhere.
    const noon = new Date("2026-10-16T12:00:00Z");
    expect(localClock(noon, "Europe/London")).toEqual({ hour: 13, minute: 0, dayStart: new Date("2026-10-15T23:00:00Z") });
    expect(localClock(noon, "Europe/Kyiv")).toEqual({ hour: 15, minute: 0, dayStart: new Date("2026-10-15T21:00:00Z") });
    expect(localClock(noon, "Europe/Madrid").hour).toBe(14);
    expect(localClock(noon, "Europe/Berlin").hour).toBe(14);
    // After the clocks go back on 25 Oct: London is on UTC, Kyiv on UTC+2.
    const winter = new Date("2026-10-26T07:30:00Z");
    expect(localClock(winter, "Europe/London")).toEqual({ hour: 7, minute: 30, dayStart: new Date("2026-10-26T00:00:00Z") });
    expect(localClock(winter, "Europe/Kyiv")).toEqual({ hour: 9, minute: 30, dayStart: new Date("2026-10-25T22:00:00Z") });
    // Midnight is "00", not "24".
    expect(localClock(new Date("2026-10-26T00:00:00Z"), "Europe/London").hour).toBe(0);
  });

  it("reads the state through push_log's index, breaking news through its own index, the top story through added_at", async () => {
    const plan = async (sql: string, ...binds: unknown[]) =>
      (await env.DB.prepare(`EXPLAIN QUERY PLAN ${sql}`).bind(...binds).all<{ detail: string }>()).results.map((r) => r.detail).join("; ");
    const state = await plan(PUSH_STATE, JSON.stringify([{ lang: "en", dayStart: stored(london(0)) }]));
    expect(state).toContain("push_log_lang_time");
    for (const [sql, index] of [[BREAKING_CANDIDATE, "articles_breaking"], [TOP_CANDIDATE, "articles_added_at"]]) {
      const candidate = await plan(sql, "uk", stored(london(0)), stored(london(0, 0, 9)));
      expect(candidate).toContain(`SEARCH a USING INDEX ${index} (added_at>?)`);
      expect(candidate).toContain("sqlite_autoindex_article_translations_1");
      expect(candidate).toContain("sqlite_autoindex_push_log_1");
    }
  });

  it("reads few D1 rows in a run that sends nothing, with a day of news in four languages", async () => {
    await only("uk", "ru", "es");
    // 50 decisions in 24 hours, 5 of them breaking and already pushed (yesterday) in every language.
    for (let i = 0; i < 50; i++) {
      const id = `n${String(i).padStart(2, "0")}`;
      const breaking = i % 10 === 0;
      await decision(id, breaking ? 4 : 2, later(london(11, 30, 15), i * 25));
      for (const lang of ["uk", "ru", "es"] as const) await translated(id, lang);
      if (breaking) {
        for (const lang of ["en", "uk", "ru", "es"]) {
          await env.DB.prepare("INSERT INTO push_log (article_id, lang, sent_at, topic, message_id) VALUES (?1, ?2, ?3, 'breaking_' || ?2, 'm')")
            .bind(id, lang, stored(london(20, 0, 15)))
            .run();
        }
      }
    }
    const google = fakeGoogle();
    quiet();
    const rows = await d1Rows(() => push(london(11), google));
    expect(rows.written).toBe(0);
    // 61 on 16 Oct (209 before breaking news had its own index): the push_log state, and per language
    // the 5 breaking decisions with their lookups. About 450 runs a day are outside every quiet hour.
    expect(rows.read).toBeLessThan(80);
  });
});

describe("the scheduled runs", () => {
  const keyless = () => ({ ...testEnv(null, undefined, null) });

  it("ends with the push step, after the release; without the secret it logs that it skipped", async () => {
    await insertNews("a1", stored(new Date(Date.now() - 3_600_000)));
    const log = quiet();
    await worker.scheduled(createScheduledController({ cron: CRONS.translator }), { ...keyless(), FCM_SERVICE_ACCOUNT: undefined });
    expect(await env.DB.prepare("SELECT feed_seq FROM articles WHERE id = 'a1'").first("feed_seq")).toEqual(expect.any(Number));
    const messages = log.mock.calls.map((c) => JSON.parse(String(c[0])).message);
    expect(messages.at(-1)).toBe("push skipped: FCM_SERVICE_ACCOUNT not set");
  });

  it("never lets a push error break the translator's run or its release", async () => {
    await insertNews("a1", stored(new Date(Date.now() - 3_600_000)));
    quiet();
    const errors = vi.spyOn(console, "error").mockImplementation(() => {});
    const broken = keyless();
    Object.defineProperty(broken, "FCM_SERVICE_ACCOUNT", {
      get() {
        throw new Error("push broke");
      },
    });
    await expect(worker.scheduled(createScheduledController({ cron: CRONS.translator }), broken)).resolves.toBeUndefined();
    expect(await env.DB.prepare("SELECT feed_seq FROM articles WHERE id = 'a1'").first("feed_seq")).toEqual(expect.any(Number));
    expect(errors.mock.calls.map((c) => JSON.parse(String(c[0])))).toEqual([{ message: "push error", error: "push broke" }]);
  });

  it("sends from the summarizer's run while the translator is not running, and leaves it to the translator once it runs", async () => {
    const log = quiet();
    const summarizer = async () => {
      log.mockClear();
      await worker.scheduled(createScheduledController({ cron: CRONS.summarizer }), { ...keyless(), FCM_SERVICE_ACCOUNT: undefined });
      return log.mock.calls.map((c) => JSON.parse(String(c[0])).message);
    };
    const translatorRan = (minutesAgo: number) =>
      env.DB.prepare("INSERT INTO step_runs (step, at) VALUES ('translator', ?1) ON CONFLICT (step) DO UPDATE SET at = excluded.at")
        .bind(stored(new Date(Date.now() - minutesAgo * 60_000)))
        .run();
    await env.DB.prepare("DELETE FROM step_runs").run();
    // The push step ran (and, without the secret, said so).
    expect(await summarizer()).toContain("push skipped: FCM_SERVICE_ACCOUNT not set");
    await translatorRan(11);
    expect(await summarizer()).toContain("push skipped: FCM_SERVICE_ACCOUNT not set");
    await translatorRan(9);
    expect(await summarizer()).not.toContain("push skipped: FCM_SERVICE_ACCOUNT not set");
  });
});

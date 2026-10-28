import { env, exports } from "cloudflare:workers";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { BUNDLE_ID, CHAT_PRODUCT_ID, receiveNotification } from "../src/appstore";
import { DAILY_QUESTIONS, QUESTION_MICROS, chatStatus, creditChatPack } from "../src/chat";
import { charge, costMicros } from "../src/chat/usage";
import { runCleanup } from "../src/health/cleanup";
import { testAppStore, type TestAppStore } from "./apple-pki";

const DAY = 86_400_000;
const NOW = new Date("2026-10-27T12:00:00Z");
const PACK_50 = "com.officialnews.app.agent.questions50";

/** A month of the chat's subscription, bought yesterday, as the App Store signs it. */
const transaction = (changes: object = {}) => ({
  originalTransactionId: "2000000001",
  transactionId: "2000000001",
  bundleId: BUNDLE_ID,
  productId: CHAT_PRODUCT_ID,
  environment: "Production",
  expiresDate: NOW.getTime() + 29 * DAY,
  signedDate: NOW.getTime() - DAY,
  ...changes,
});

/** A pack of 50 questions, bought today. */
const pack = (changes: object = {}) => ({
  originalTransactionId: "3000000001",
  transactionId: "3000000001",
  bundleId: BUNDLE_ID,
  productId: PACK_50,
  environment: "Production",
  type: "Consumable",
  signedDate: NOW.getTime() - 1000,
  ...changes,
});

let store: TestAppStore;
beforeAll(async () => {
  store = await testAppStore();
});
const trusted = () => ({ rootSha256: store.rootSha256, now: NOW });

/** A released decision with its official text of `chars` characters, translated into Ukrainian. */
async function decision(chars = 70) {
  await env.DB.prepare("DELETE FROM article_translations WHERE article_id = 'c1'").run();
  await env.DB.prepare("DELETE FROM articles WHERE id = 'c1'").run();
  const text = "The official text: Euro 7 applies to new cars from 29 November 2027.".padEnd(chars, " Lorem ipsum.");
  await env.DB.prepare(
    `INSERT INTO articles (id, source_id, url, original_title, published_at, fetched_at, headline, short_summary, summary, text,
                           is_news, importance, decision_type, summarized_at, topics, tags, feed_seq, added_at)
     VALUES ('c1', 'de-federal-government', 'https://example.gov/c1', 'Euro 7 for new cars', '2026-10-26T08:00:00Z', '2026-10-26T08:00:00Z',
             'New cars must meet Euro 7 from 2027', 'Short.', 'From November 2027 new cars and vans must meet Euro 7.',
             ?1, 1, 3, 'decision', '2026-10-26T08:00:00Z', '[]', '[]',
             (SELECT COALESCE(MAX(feed_seq), 0) + 1 FROM articles WHERE feed_seq IS NOT NULL), '2026-10-26T08:00:00Z')`,
  )
    .bind(text)
    .run();
  await env.DB.prepare(
    `INSERT INTO article_translations (article_id, lang, headline, short_summary, summary, model, source_summarized_at,
                                       attempts_source, lang_seq, translated_at, published_at, state, state_at)
     VALUES ('c1', 'uk', 'Нові авто мають відповідати Євро-7 з 2027 року', 'Коротко.', 'З листопада 2027 року нові авто мають відповідати Євро-7.',
             'groq:x', '2026-10-26T08:00:00Z', '2026-10-26T08:00:00Z',
             (SELECT COALESCE(MAX(lang_seq), 0) + 1 FROM article_translations WHERE lang = 'uk'),
             '2026-10-26T08:00:00Z', '2026-10-26T08:00:00Z', 'published', '2026-10-26T08:00:00Z')`,
  ).run();
}
beforeEach(() => decision());

/** What one answer of 1,500 tokens in and 200 out costs at OpenAI, in micro-dollars. */
const COST = costMicros({ prompt_tokens: 1500, completion_tokens: 200 });

const wallet = () => env.DB.prepare("SELECT extra_micros FROM chat_wallet WHERE original_transaction_id = '2000000001'").first<number>("extra_micros");
const spendToday = (micros: number) =>
  env.DB.prepare("INSERT INTO chat_usage (original_transaction_id, day, questions, spent_micros) VALUES ('2000000001', '2026-10-27', 20, ?)")
    .bind(micros)
    .run();
const buy = async (changes: object = {}) =>
  creditChatPack({ pack: await store.sign(pack(changes)), transaction: await store.sign(transaction()) }, env, trusted());
const status = async (sold = transaction()) => chatStatus({ articleId: "c1", transaction: await store.sign(sold) }, env, trusted());

describe("POST /v1/chat/status (#146)", () => {
  it("says what is left today, the bought questions, and how much of the limit one question about this article takes", async () => {
    expect(await status()).toEqual({ status: 200, body: { questionsLeft: 20, boughtQuestions: 0, units: 1, resetsAt: "2026-10-28T00:00:00Z" } });
    await spendToday(17 * QUESTION_MICROS);
    await buy();
    expect((await status()).body).toMatchObject({ questionsLeft: 3, boughtQuestions: 50 });
    await decision(20_000);
    expect((await status()).body).toMatchObject({ questionsLeft: 1, boughtQuestions: 16, units: 3 });
    // Another subscription, expired: an older transaction of this one would not close it.
    expect(await status(transaction({ originalTransactionId: "2000000099", transactionId: "2000000099", expiresDate: NOW.getTime() - 1000 }))).toMatchObject({
      status: 402,
    });
    expect(await chatStatus({ articleId: "nope", transaction: await store.sign(transaction()) }, env, trusted())).toMatchObject({ status: 404 });
  });

  it("through the Worker: POST only, JSON errors, Apple's root only", async () => {
    for (const path of ["/v1/chat/status", "/v1/chat/credits"]) {
      const get = await exports.default.fetch(`https://api.test${path}`);
      expect(get.status).toBe(405);
      expect(get.headers.get("allow")).toBe("POST");
    }
    const post = (path: string, body: string) => exports.default.fetch(`https://api.test${path}`, { method: "POST", body });
    const garbage = await post("/v1/chat/status", "{");
    expect(garbage.status).toBe(400);
    expect(garbage.headers.get("cache-control")).toBe("no-store");
    expect((await post("/v1/chat/status", JSON.stringify({ articleId: "c1", transaction: await store.sign(transaction()) }))).status).toBe(402);
    expect((await post("/v1/chat/credits", JSON.stringify({ pack: await store.sign(pack()), transaction: await store.sign(transaction()) }))).status).toBe(400);
  });

  it("forgets the daily counts after a week", async () => {
    await env.DB.prepare("INSERT INTO chat_usage (original_transaction_id, day, questions) VALUES ('2000000001', '2026-10-01', 3), ('2000000001', '2026-10-27', 1)").run();
    await runCleanup(env, NOW);
    const { results } = await env.DB.prepare("SELECT day FROM chat_usage").all<{ day: string }>();
    expect(results.map((r) => r.day)).toEqual(["2026-10-27"]);
  });
});

describe("packs of questions (#146)", () => {
  const notify = async (type: string, changes: object) =>
    receiveNotification(
      {
        signedPayload: await store.sign({
          notificationType: type,
          data: { bundleId: BUNDLE_ID, environment: "Production", signedTransactionInfo: await store.sign(pack(changes)) },
          signedDate: NOW.getTime(),
        }),
      },
      env,
      trusted(),
    );

  it("are credited once to the subscription's wallet, however often the app sends them", async () => {
    expect(await buy()).toEqual({ status: 200, body: { credited: true, boughtQuestions: 50 } });
    expect(await buy()).toEqual({ status: 200, body: { credited: false, boughtQuestions: 50 } });
    expect((await buy({ transactionId: "3000000002", productId: "com.officialnews.app.agent.questions200" })).body).toMatchObject({ boughtQuestions: 250 });
    expect(await wallet()).toBe(250 * QUESTION_MICROS);
  });

  it("refuses what is not a pack of this app, a pack without a subscription, and a refunded pack", async () => {
    expect(await buy({ productId: CHAT_PRODUCT_ID })).toMatchObject({ status: 400 });
    expect(await buy({ bundleId: "com.example.other" })).toMatchObject({ status: 400 });
    expect(await creditChatPack({ pack: await store.sign(pack()), transaction: "not.a.jws" }, env, trusted())).toMatchObject({ status: 402 });
    expect((await buy({ revocationDate: NOW.getTime() })).body).toMatchObject({ credited: false, boughtQuestions: 0 });
  });

  it("a refund takes a pack back out of the wallet, below zero when already spent; Apple's reversal puts it back", async () => {
    await buy();
    await spendToday(DAILY_QUESTIONS * QUESTION_MICROS);
    // A question once today's budget is spent: it is paid from the pack.
    await charge(env, "2000000001", "2026-10-27", COST, NOW, true);
    expect((await notify("REFUND", { revocationDate: NOW.getTime() })).status).toBe(200);
    expect(await wallet()).toBe(-COST);
    // Apple may send it again: taken once.
    await notify("REFUND", { revocationDate: NOW.getTime() });
    expect(await wallet()).toBe(-COST);
    expect((await status()).body).toMatchObject({ questionsLeft: 0, boughtQuestions: 0 });
    await notify("REFUND_REVERSED", {});
    expect(await wallet()).toBe(50 * QUESTION_MICROS - COST);
    // A pack never credited has nothing to take back.
    await notify("REFUND", { transactionId: "3000000009", revocationDate: NOW.getTime() });
    expect(await wallet()).toBe(50 * QUESTION_MICROS - COST);
  });
});

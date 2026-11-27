// The AI chat bought on Google Play (#349): Google's answers are faked here,
// the rest (subscriptions, weeks, packs, wallets) is the chat's own code on the
// test database.
import { env } from "cloudflare:workers";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { CHAT_PRODUCT_ID } from "../src/appstore";
import { QUESTION_MICROS, WEEKLY_MICROS, chatStatus, creditChatPack } from "../src/chat";
import { firstOrder } from "../src/googleplay";
import { insertArticle, testId } from "./site-helpers";

const DAY = 86_400_000;
const NOW = new Date("2026-11-27T12:00:00Z");
const PACK = "com.officialnews.app.agent.questions50";
const WEEK_QUESTIONS = WEEKLY_MICROS / QUESTION_MICROS;
const ORDER = "GPA.3300-1111-2222-33333";
const ARTICLE = testId(349);

let serviceAccount = "";
beforeAll(async () => {
  const pair = (await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
  const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  let binary = "";
  for (const byte of der) binary += String.fromCharCode(byte);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(binary).match(/.{1,64}/g)!.join("\n")}\n-----END PRIVATE KEY-----\n`;
  serviceAccount = JSON.stringify({ type: "service_account", project_id: "p", client_email: "play@p.iam.gserviceaccount.com", private_key: pem });
});
beforeEach(async () => {
  await env.DB.prepare("DELETE FROM kv_cache WHERE key LIKE 'play_token:%'").run();
  await insertArticle({ id: ARTICLE });
});

const playEnv = () => ({ ...env, PLAY_SERVICE_ACCOUNT: serviceAccount });

/** Google: its token endpoint, then the purchases this test gives it; every call is kept in `calls`. */
function google(purchases: Record<string, { status?: number; body?: object }>) {
  const calls: { method: string; url: string }[] = [];
  const fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    const method = init?.method ?? "GET";
    calls.push({ method, url });
    if (url.startsWith("https://oauth2.googleapis.com/token")) return Response.json({ access_token: "at", expires_in: 3600 });
    for (const [part, answer] of Object.entries(purchases)) {
      if (url.includes(part)) return answer.body ? Response.json(answer.body, { status: answer.status ?? 200 }) : new Response("", { status: answer.status ?? 200 });
    }
    return new Response("", { status: 404 });
  }) as typeof globalThis.fetch;
  return { fetch, calls };
}

/** The chat's subscription as Google's subscriptionsv2 shows it: bought today, paid until in 30 days. */
const subscription = (changes: object = {}) => ({
  subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
  latestOrderId: ORDER,
  acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
  lineItems: [{ productId: CHAT_PRODUCT_ID, expiryTime: new Date(NOW.getTime() + 30 * DAY).toISOString(), latestSuccessfulOrderId: ORDER }],
  ...changes,
});

const status = (g: ReturnType<typeof google>, transaction = "gp:sub-token") =>
  chatStatus({ articleId: ARTICLE, transaction }, playEnv(), { now: NOW, playFetch: g.fetch });

describe("the AI chat bought on Google Play (#349)", () => {
  it("a paid subscription gets the same week as on the App Store, kept under its first order", async () => {
    const g = google({ "/subscriptionsv2/tokens/sub-token": { body: subscription() } });
    expect(await status(g)).toMatchObject({ status: 200, body: { questionsLeft: WEEK_QUESTIONS, limitReached: false } });
    const row = await env.DB.prepare("SELECT environment, product_id FROM subscriptions WHERE original_transaction_id = ?").bind(`gp:${ORDER}`).first();
    expect(row).toEqual({ environment: "Production", product_id: CHAT_PRODUCT_ID });
  });

  it("a renewal (order `..1`) stays the same subscription", async () => {
    expect(firstOrder(`${ORDER}..12`)).toBe(ORDER);
    const later = new Date(NOW.getTime() + 60 * DAY).toISOString();
    const g = google({
      "/subscriptionsv2/tokens/sub-token": { body: subscription({ latestOrderId: `${ORDER}..1`, lineItems: [{ productId: CHAT_PRODUCT_ID, expiryTime: later, latestSuccessfulOrderId: `${ORDER}..1` }] }) },
    });
    expect((await status(g)).status).toBe(200);
    const row = await env.DB.prepare("SELECT transaction_id FROM subscriptions WHERE original_transaction_id = ?").bind(`gp:${ORDER}`).first();
    expect(row).toEqual({ transaction_id: `gp:${ORDER}..1` });
  });

  it("acknowledges a new subscription, so Google does not refund it after 3 days", async () => {
    const g = google({
      ":acknowledge": { status: 200 },
      "/subscriptionsv2/tokens/sub-token": { body: subscription({ acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING" }) },
    });
    expect((await status(g)).status).toBe(200);
    expect(g.calls.filter((c) => c.method === "POST" && c.url.endsWith(`/subscriptions/${CHAT_PRODUCT_ID}/tokens/sub-token:acknowledge`))).toHaveLength(1);
  });

  it("refuses an unknown token, an expired, a pending or a revoked subscription, and another product", async () => {
    const expired = subscription({ subscriptionState: "SUBSCRIPTION_STATE_EXPIRED", lineItems: [{ productId: CHAT_PRODUCT_ID, expiryTime: "2026-11-01T00:00:00Z" }] });
    for (const body of [
      undefined,
      expired,
      subscription({ subscriptionState: "SUBSCRIPTION_STATE_PENDING" }),
      subscription({ lineItems: [{ productId: "com.example.other", expiryTime: "2027-01-01T00:00:00Z" }] }),
    ]) {
      const g = google(body ? { "/subscriptionsv2/tokens/sub-token": { body } } : {});
      expect(await status(g)).toMatchObject({ status: 402 });
    }
    // Paid first, then refunded and revoked: no longer paid.
    expect((await status(google({ "/subscriptionsv2/tokens/sub-token": { body: subscription() } }))).status).toBe(200);
    const revoked = google({ "/subscriptionsv2/tokens/sub-token": { body: subscription({ subscriptionState: "SUBSCRIPTION_STATE_REVOKED" }) } });
    expect(await status(revoked)).toMatchObject({ status: 402 });
  });

  it("answers 503 when Google or the robot cannot be asked, so the app tries again", async () => {
    const g = google({ "/subscriptionsv2/tokens/sub-token": { status: 500, body: {} } });
    expect(await status(g)).toMatchObject({ status: 503 });
    const noRobot = await chatStatus({ articleId: ARTICLE, transaction: "gp:sub-token" }, env, { now: NOW, playFetch: g.fetch });
    expect(noRobot).toMatchObject({ status: 503 });
  });

  it("a test purchase (the closed test, license testers) counts as Sandbox", async () => {
    const g = google({ "/subscriptionsv2/tokens/sub-token": { body: subscription({ testPurchase: {} }) } });
    expect((await status(g)).status).toBe(200);
    const row = await env.DB.prepare("SELECT environment FROM subscriptions WHERE original_transaction_id = ?").bind(`gp:${ORDER}`).first();
    expect(row).toEqual({ environment: "Sandbox" });
  });

  it("a pack is credited once, then consumed so it can be bought again", async () => {
    const g = google({
      "/subscriptionsv2/tokens/sub-token": { body: subscription() },
      ":consume": { status: 200 },
      [`/products/${PACK}/tokens/pack-token`]: { body: { purchaseState: 0, orderId: "GPA.3300-9999-0000-11111", purchaseType: undefined } },
    });
    const buy = () => creditChatPack({ pack: `gp:${PACK}:pack-token`, transaction: "gp:sub-token" }, playEnv(), { now: NOW, playFetch: g.fetch });
    expect(await buy()).toEqual({ status: 200, body: { credited: true, boughtQuestions: WEEK_QUESTIONS, extraUsage: true } });
    expect(await buy()).toEqual({ status: 200, body: { credited: false, boughtQuestions: WEEK_QUESTIONS, extraUsage: true } });
    expect(g.calls.filter((c) => c.method === "POST" && c.url.endsWith(`/products/${PACK}/tokens/pack-token:consume`)).length).toBeGreaterThan(0);
  });

  it("refuses a pack not paid, a pack of another product, and a pack and subscription from different stores", async () => {
    const g = google({
      "/subscriptionsv2/tokens/sub-token": { body: subscription() },
      [`/products/${PACK}/tokens/pending`]: { body: { purchaseState: 2, orderId: "GPA.1" } },
    });
    const buy = (pack: string, transaction = "gp:sub-token") => creditChatPack({ pack, transaction }, playEnv(), { now: NOW, playFetch: g.fetch });
    expect(await buy(`gp:${PACK}:pending`)).toMatchObject({ status: 400 });
    expect(await buy(`gp:${CHAT_PRODUCT_ID}:x`)).toMatchObject({ status: 400 });
    expect(await buy(`gp:${PACK}:pack-token`, "an.apple.jws")).toMatchObject({ status: 403 });
  });
});

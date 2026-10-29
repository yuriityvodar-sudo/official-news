// Messages from readers (#220): the API's rules, the push for our reply and
// the 90-day cleanup. Google's token endpoint and FCM are fakes; the service
// account's key is made for this test run only.
import { env, exports } from "cloudflare:workers";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { messagePost } from "../src/admin/messages";
import type { AdminEnv } from "../src/admin/env";
import { runCleanup } from "../src/health/cleanup";
import { TOKEN_URL, fcmUrl } from "../src/push/fcm";
import { DAILY_MESSAGES, postSupportMessage, sha256, supportThread } from "../src/support";
import { REPLY_PUSHES_PER_RUN, cleanupSupport, sendReplyPushes } from "../src/support/cron";

const DEVICE = "device-0123456789abcdef0123456789abcdef";
const OTHER = "other_device_0123456789abcdef0123456789";
const T0 = new Date("2026-10-29T10:00:00Z");
const later = (date: Date, days: number) => new Date(date.getTime() + days * 86_400_000);
const at = (date: Date) => `${date.toISOString().slice(0, 19)}Z`;
const body = (over: Record<string, unknown> = {}) => ({ device: DEVICE, text: "Hello, the feed is empty.", lang: "uk", app: "1.0.0 (47)", ...over });
const send = (over: Record<string, unknown> = {}, now = T0, ip = "203.0.113.7") => postSupportMessage(body(over), ip, env, now);
const admin = env as unknown as AdminEnv;
const threadId = async (device = DEVICE) =>
  (await env.DB.prepare("SELECT id FROM support_threads WHERE device_hash = ? ORDER BY created_at DESC LIMIT 1").bind(await sha256(device)).first<string>("id"))!;
const reply = async (text: string, now: Date, device = DEVICE) => {
  const form = new FormData();
  form.set("thread", await threadId(device));
  form.set("text", text);
  return messagePost("/messages/reply", form, admin, now);
};
const close = async (now: Date) => {
  const form = new FormData();
  form.set("thread", await threadId());
  return messagePost("/messages/close", form, admin, now);
};

afterEach(() => {
  vi.restoreAllMocks();
});

describe("POST /v1/support/messages", () => {
  it("starts a conversation: waiting, locked for 7 days, the phone's id stored only as its hash", async () => {
    const { status, body: answer } = await send({ text: "  Hello, the feed is empty.  ", push: "fcm-token-1" });
    expect(status).toBe(200);
    expect(answer).toEqual({
      thread: {
        status: "waiting",
        messages: [{ from: "reader", text: "Hello, the feed is empty.", at: at(T0) }],
        canWrite: false,
        writeAfter: at(later(T0, 7)),
      },
    });
    const row = await env.DB.prepare("SELECT * FROM support_threads").first<Record<string, unknown>>();
    expect(row).toMatchObject({ device_hash: await sha256(DEVICE), status: "waiting", lang: "uk", app: "1.0.0 (47)", push_token: "fcm-token-1", reply_push_pending: 0 });
    const everything = JSON.stringify([row, (await env.DB.prepare("SELECT * FROM support_messages").all()).results]);
    expect(everything).not.toContain(DEVICE);
    expect(everything).not.toContain("203.0.113.7");
  });

  it("answers 409 with writeAfter while the reader waits for our reply", async () => {
    await send();
    const { status, body: answer } = await send({ text: "Anyone?" }, later(T0, 6.9));
    expect(status).toBe(409);
    expect(answer).toEqual({ error: "Waiting for our reply", writeAfter: at(later(T0, 7)) });
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM support_messages").first("n"))).toBe(1);
  });

  it("continues the same conversation after our reply, and keeps the push token when none is sent", async () => {
    await send({ push: "fcm-token-1" });
    await reply("Thanks, <b>fixed</b> now.", later(T0, 1));
    const { status, body: answer } = await send({ text: "Works, thanks!", lang: "en", app: "1.0.0 (48)" }, later(T0, 2));
    expect(status).toBe(200);
    expect(answer.thread).toMatchObject({ status: "waiting", canWrite: false, writeAfter: at(later(T0, 9)) });
    expect((answer.thread as { messages: { from: string }[] }).messages.map((m) => m.from)).toEqual(["reader", "team", "reader"]);
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM support_threads").first("n")).toBe(1);
    expect(await env.DB.prepare("SELECT lang, app, push_token, reply_push_pending FROM support_threads").first()).toEqual({
      lang: "en",
      app: "1.0.0 (48)",
      push_token: "fcm-token-1",
      // The reader already saw the reply: no push for it any more.
      reply_push_pending: 0,
    });
  });

  it("lets the reader write again 7 days after their latest message, in the same conversation", async () => {
    await send();
    const { status, body: answer } = await send({ text: "Still there?" }, later(T0, 7));
    expect(status).toBe(200);
    expect((answer.thread as { messages: unknown[] }).messages).toHaveLength(2);
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM support_threads").first("n")).toBe(1);
  });

  it("starts a new conversation after we closed one, and GET shows only the new one", async () => {
    await send();
    await close(later(T0, 1));
    const closed = await supportThread(DEVICE, env, later(T0, 1));
    expect(closed.body.thread).toMatchObject({ status: "closed", canWrite: true, writeAfter: null });
    const { status } = await send({ text: "A new question." }, later(T0, 2));
    expect(status).toBe(200);
    expect(await env.DB.prepare("SELECT status FROM support_threads ORDER BY created_at").all()).toMatchObject({ results: [{ status: "closed" }, { status: "waiting" }] });
    const { body: answer } = await supportThread(DEVICE, env, later(T0, 2));
    expect(answer.thread).toMatchObject({ status: "waiting", messages: [{ from: "reader", text: "A new question." }] });
  });

  it("answers 429 after 5 messages a UTC day from one address, and takes more the next day or from another address", async () => {
    for (let i = 0; i < DAILY_MESSAGES; i++) {
      expect((await postSupportMessage(body({ device: `${"d".repeat(31)}${i}` }), "198.51.100.1", env, T0)).status).toBe(200);
    }
    const sixth = await postSupportMessage(body({ device: `${"d".repeat(31)}x` }), "198.51.100.1", env, T0);
    expect(sixth).toEqual({ status: 429, body: { error: "Too many messages today", resetsAt: "2026-10-30T00:00:00Z" } });
    expect((await postSupportMessage(body({ device: `${"d".repeat(31)}x` }), "198.51.100.2", env, T0)).status).toBe(200);
    expect((await postSupportMessage(body({ device: `${"d".repeat(31)}y` }), "198.51.100.1", env, new Date("2026-10-30T00:00:01Z"))).status).toBe(200);
  });

  it("refuses a bad body with 400", async () => {
    const bad = [
      null,
      "text",
      [],
      body({ device: "short" }),
      body({ device: `${"a".repeat(31)}!` }),
      body({ device: "a".repeat(129) }),
      body({ text: "   " }),
      body({ text: "x".repeat(2001) }),
      body({ text: 5 }),
      body({ lang: "fr" }),
      body({ app: "x".repeat(33) }),
      body({ app: undefined }),
      body({ push: 5 }),
      body({ push: "x".repeat(4097) }),
    ];
    for (const b of bad) {
      const answer = await postSupportMessage(b, "203.0.113.7", env, T0);
      expect(answer.status, JSON.stringify(b)?.slice(0, 60)).toBe(400);
      expect(typeof answer.body.error).toBe("string");
    }
    // 2,000 characters are fine, counted as characters, not UTF-16 units.
    expect((await send({ text: "é".repeat(1000) + "😀".repeat(1000) })).status).toBe(200);
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM support_messages").first("n")).toBe(1);
  });

  it("lets only one of two sends at once through, for one phone and for the day's last message of an address", async () => {
    const both = await Promise.all([send({ text: "One" }), send({ text: "Two" })]);
    expect(both.map((a) => a.status).sort()).toEqual([200, 409]);
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM support_messages").first("n")).toBe(1);

    // One message from the address so far: 4 more fit, so of 6 phones at once, 2 are refused.
    const many = await Promise.all(
      Array.from({ length: 6 }, (_, i) => postSupportMessage(body({ device: `${"e".repeat(31)}${i}` }), "203.0.113.7", env, T0)),
    );
    expect(many.map((a) => a.status).sort()).toEqual([200, 200, 200, 200, 429, 429]);
  });
});

describe("the support routes", () => {
  const fetch = (path: string, init?: RequestInit) => exports.default.fetch(`https://api.test${path}`, init);

  it("posts and reads back by the X-Support-Device header, never cached", async () => {
    const posted = await fetch("/v1/support/messages", {
      method: "POST",
      headers: { "content-type": "application/json", "cf-connecting-ip": "203.0.113.9" },
      body: JSON.stringify(body()),
    });
    expect(posted.status).toBe(200);
    expect(posted.headers.get("cache-control")).toBe("no-store");
    const read = await fetch("/v1/support/thread", { headers: { "x-support-device": DEVICE } });
    expect(read.status).toBe(200);
    expect(read.headers.get("cache-control")).toBe("no-store");
    expect(((await read.json()) as { thread: { status: string } }).thread.status).toBe("waiting");
    const none = await fetch("/v1/support/thread", { headers: { "x-support-device": OTHER } });
    expect(await none.json()).toEqual({ thread: null });
  });

  it("answers 400 without a valid header, 400 for a body that is not JSON, 405 for other methods", async () => {
    expect((await fetch("/v1/support/thread")).status).toBe(400);
    expect((await fetch("/v1/support/thread", { headers: { "x-support-device": "short" } })).status).toBe(400);
    expect((await fetch(`/v1/support/thread?device=${DEVICE}`)).status).toBe(400);
    expect((await fetch("/v1/support/messages", { method: "POST", body: "not json" })).status).toBe(400);
    expect((await fetch("/v1/support/messages")).status).toBe(405);
    expect((await fetch("/v1/support/thread", { method: "POST" })).status).toBe(405);
  });
});

const PROJECT = "official-news-48e16";
let serviceAccount: string;

beforeAll(async () => {
  const pair = (await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
  const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----\n`;
  serviceAccount = JSON.stringify({ project_id: PROJECT, client_email: `fcm-sender@${PROJECT}.iam.gserviceaccount.com`, private_key: pem });
});

/** Google's token endpoint and FCM: FCM answers each message with the next of `fcm`, else accepts it. */
function fakeGoogle(fcm: { status: number; body?: unknown }[] = []) {
  const messages: { message: Record<string, unknown> }[] = [];
  const fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    if (url === TOKEN_URL) return Response.json({ access_token: "token-1", expires_in: 3599 });
    if (url === fcmUrl(PROJECT)) {
      messages.push(JSON.parse(String(init?.body)));
      const next = fcm.shift() ?? { status: 200, body: { name: `projects/${PROJECT}/messages/${messages.length}` } };
      return Response.json(next.body ?? {}, { status: next.status });
    }
    throw new Error(`unexpected request to ${url}`);
  }) as typeof globalThis.fetch;
  return { fetch, messages };
}

const pushEnv = () => ({ ...env, FCM_SERVICE_ACCOUNT: serviceAccount });
const pending = async () => (await env.DB.prepare("SELECT reply_push_pending AS p, push_token AS t FROM support_threads").first<{ p: number; t: string | null }>())!;

describe("the push for our reply", () => {
  it("goes to the phone's token in the reader's language, with data type support, once", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    await send({ push: "fcm-token-1" });
    await reply("Fixed now, thank you for writing.", later(T0, 1));
    expect((await pending()).p).toBe(1);
    const google = fakeGoogle();
    expect(await sendReplyPushes(pushEnv(), { now: later(T0, 1), fetch: google.fetch })).toEqual({ sent: 1, dropped: 0 });
    expect(google.messages).toEqual([
      {
        message: {
          token: "fcm-token-1",
          notification: { title: "Outer News відповіли на ваше повідомлення", body: "Fixed now, thank you for writing." },
          data: { type: "support" },
          apns: { payload: { aps: { sound: "default" } } },
        },
      },
    ]);
    expect((await pending()).p).toBe(0);
    // Nothing left: the next run reads one index and sends nothing.
    await sendReplyPushes(pushEnv(), { now: later(T0, 1), fetch: google.fetch });
    expect(google.messages).toHaveLength(1);
  });

  it("is dropped without a token, forgets a token FCM refuses, and waits when FCM cannot take it now", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    await send();
    await reply("Hi", later(T0, 1));
    const google = fakeGoogle();
    expect(await sendReplyPushes(pushEnv(), { now: later(T0, 1), fetch: google.fetch })).toMatchObject({ sent: 0, dropped: 1 });
    expect(google.messages).toEqual([]);
    expect((await pending()).p).toBe(0);

    await send({ text: "Again", push: "stale-token" }, later(T0, 2));
    await reply("Hi again", later(T0, 3));
    const refusing = fakeGoogle([{ status: 404, body: { error: { status: "NOT_FOUND", message: "Requested entity was not found." } } }]);
    expect(await sendReplyPushes(pushEnv(), { now: later(T0, 3), fetch: refusing.fetch })).toMatchObject({ sent: 0, dropped: 1 });
    expect(await pending()).toEqual({ p: 0, t: null });

    await send({ text: "Third", push: "fcm-token-2" }, later(T0, 4));
    await reply("Third reply", later(T0, 5));
    const busy = fakeGoogle([{ status: 503, body: { error: { status: "UNAVAILABLE" } } }]);
    expect(await sendReplyPushes(pushEnv(), { now: later(T0, 5), fetch: busy.fetch })).toMatchObject({ sent: 0, dropped: 0, skipped: "FCM: HTTP 503 UNAVAILABLE" });
    expect(await pending()).toEqual({ p: 1, t: "fcm-token-2" });
    // Paused for 10 minutes, then sent.
    const after = fakeGoogle();
    expect(await sendReplyPushes(pushEnv(), { now: later(T0, 5), fetch: after.fetch })).toMatchObject({ sent: 0, skipped: expect.stringContaining("paused") });
    expect(await sendReplyPushes(pushEnv(), { now: new Date(later(T0, 5).getTime() + 11 * 60_000), fetch: after.fetch })).toMatchObject({ sent: 1 });
  });

  it("waits for the Worker secret, and sends at most a few a run", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    for (let i = 0; i < REPLY_PUSHES_PER_RUN + 1; i++) {
      const device = `${"f".repeat(31)}${i}`;
      await send({ device, push: `token-${i}` }, T0, `192.0.2.${i}`);
      await reply("Answer", later(T0, 1), device);
    }
    expect(await sendReplyPushes({ ...env, FCM_SERVICE_ACCOUNT: undefined }, { now: later(T0, 1) })).toMatchObject({ skipped: "FCM_SERVICE_ACCOUNT not set" });
    const google = fakeGoogle();
    expect((await sendReplyPushes(pushEnv(), { now: later(T0, 1), fetch: google.fetch })).sent).toBe(REPLY_PUSHES_PER_RUN);
    expect((await sendReplyPushes(pushEnv(), { now: later(T0, 1), fetch: google.fetch })).sent).toBe(1);
  });
});

describe("the cleanup of old conversations", () => {
  it("deletes conversations closed or quiet for 90 days with their messages, and clears past days' address hashes", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    await send({ device: `${"g".repeat(31)}1` }, T0, "192.0.2.1"); // quiet since T0
    await send({ device: `${"g".repeat(31)}2` }, T0, "192.0.2.2");
    await send({}, later(T0, 5)); // DEVICE, closed at day 6
    await close(later(T0, 6));
    await send({ device: `${"g".repeat(31)}3` }, later(T0, 80), "192.0.2.3"); // recent
    const count = async () => [
      await env.DB.prepare("SELECT COUNT(*) AS n FROM support_threads").first("n"),
      await env.DB.prepare("SELECT COUNT(*) AS n FROM support_messages").first("n"),
    ];
    expect(await count()).toEqual([4, 4]);

    expect(await cleanupSupport(env, later(T0, 90.5))).toBe(2);
    expect(await count()).toEqual([2, 2]);
    expect(await cleanupSupport(env, later(T0, 96.5))).toBe(1);
    expect(await count()).toEqual([1, 1]);
    // Only today's messages keep the address hash, for the day's count.
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM support_messages WHERE ip_day_hash IS NOT NULL").first("n")).toBe(0);

    // The daily cleanup run does it too.
    await env.DB.prepare("UPDATE support_threads SET updated_at = '2026-01-01T00:00:00Z'").run();
    await runCleanup(env, later(T0, 97));
    expect(await count()).toEqual([0, 0]);
  });
});

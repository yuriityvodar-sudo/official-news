// The scheduled side of readers' messages (#220): the push for a reply from
// us, and deleting old conversations. Both stay small: the free plan gives a
// run 10 ms of CPU and 50 outside requests.
import type { Env } from "../env";
import { toStoredTime } from "../fetcher/text";
import { shorten, type PushOptions } from "../push";
import { DROP_CACHE, accessToken, parseServiceAccount, pause, sendMessage, tokenKey } from "../push/fcm";
import type { SupportLang } from "./index";

/** At most this many reply pushes a run; the next run sends the rest. */
export const REPLY_PUSHES_PER_RUN = 3;
/** A conversation is deleted this many days after it was closed, or got its last message. */
export const KEEP_DAYS = 90;
const DAY_MS = 86_400_000;

/** The push's title in the language of the reader's latest message; the body is the start of our reply. */
export const REPLY_TITLE: Record<SupportLang, string> = {
  en: "Outer News replied to your message",
  uk: "Outer News відповіли на ваше повідомлення",
  ru: "Outer News ответили на ваше сообщение",
  es: "Outer News respondió a tu mensaje",
  de: "Outer News hat auf Ihre Nachricht geantwortet",
};

/** The replies waiting for their push, oldest first, with the reply's text. Through the partial index support_threads_push. */
const PENDING = `SELECT t.id, t.lang, t.push_token,
    (SELECT text FROM support_messages m WHERE m.thread_id = t.id AND m.sender = 'team' ORDER BY m.created_at DESC, m.rowid DESC LIMIT 1) AS reply
  FROM support_threads t WHERE t.reply_push_pending = 1 ORDER BY t.updated_at LIMIT ?1`;
/** Takes a reply's push for this run, so an overlapping run never sends it too. */
const CLAIM = "UPDATE support_threads SET reply_push_pending = 0 WHERE id = ?1 AND reply_push_pending = 1 RETURNING id";
/** Gives it back: FCM could not take it just then. */
const GIVE_BACK = "UPDATE support_threads SET reply_push_pending = 1 WHERE id = ?1";
/** FCM refused the phone's token (an app removed, a token renewed): it is not used again. */
const FORGET_TOKEN = "UPDATE support_threads SET push_token = NULL WHERE id = ?1 AND push_token = ?2";

export interface ReplyPushRun {
  sent: number;
  /** Not sent and done with: no token, or FCM refused or did not answer. */
  dropped: number;
  skipped?: string;
}

/**
 * Sends the push for our replies (reply_push_pending, set by the admin page),
 * at most REPLY_PUSHES_PER_RUN, to the phone's own FCM token, data
 * `{ type: "support" }`. Each is claimed before it is sent. A conversation
 * with no token is done at once; one FCM refused, or did not answer, too
 * (sent may be). When FCM cannot take it just then (fcm.ts, `retry`), it
 * waits for a later run and the push step pauses, as for breaking news.
 */
export async function sendReplyPushes(env: Env, options: PushOptions = {}): Promise<ReplyPushRun> {
  const now = options.now ?? new Date();
  const fetch = options.fetch ?? globalThis.fetch;
  const run: ReplyPushRun = { sent: 0, dropped: 0 };
  const { results } = await env.DB.prepare(PENDING)
    .bind(REPLY_PUSHES_PER_RUN)
    .all<{ id: string; lang: SupportLang; push_token: string | null; reply: string | null }>();
  if (!results.length) return run;
  const done = (reason: string) => {
    run.skipped = reason;
    console.log(JSON.stringify({ message: "support push run", ...run }));
    return run;
  };

  const noToken = results.filter((r) => !r.push_token);
  if (noToken.length) {
    const claims = await env.DB.batch(noToken.map((r) => env.DB.prepare(CLAIM).bind(r.id)));
    run.dropped += claims.filter((c) => c.results.length).length;
  }
  const withToken = results.filter((r) => r.push_token);
  if (!withToken.length) return done("no push token");
  if (!env.FCM_SERVICE_ACCOUNT) return done("FCM_SERVICE_ACCOUNT not set");
  let account;
  try {
    account = parseServiceAccount(env.FCM_SERVICE_ACCOUNT);
  } catch (error) {
    return done(error instanceof Error ? error.message : String(error));
  }
  // The token before any claim: while the step is paused nothing is claimed, so nothing is lost.
  const got = await accessToken(env, account, now, fetch);
  if ("error" in got) return done(got.error);

  const claims = await env.DB.batch(withToken.map((r) => env.DB.prepare(CLAIM).bind(r.id)));
  const writes: D1PreparedStatement[] = [];
  let paused = false;
  for (const [i, row] of withToken.entries()) {
    if (!claims[i].results.length) continue;
    if (paused) {
      writes.push(env.DB.prepare(GIVE_BACK).bind(row.id));
      continue;
    }
    const lang = row.lang in REPLY_TITLE ? row.lang : "en";
    const result = await sendMessage(
      account,
      got.token,
      { token: row.push_token!, title: REPLY_TITLE[lang], body: shorten(row.reply ?? ""), data: { type: "support" } },
      fetch,
    );
    if (result.ok) {
      run.sent++;
    } else if (result.outcome !== "retry") {
      run.dropped++;
      if (result.outcome === "refused") writes.push(env.DB.prepare(FORGET_TOKEN).bind(row.id, row.push_token));
    } else {
      writes.push(env.DB.prepare(GIVE_BACK).bind(row.id));
      if (result.status === 401) writes.push(env.DB.prepare(DROP_CACHE).bind(tokenKey(account)));
      writes.push(pause(env, account, now, `FCM: ${result.error}`, result.retryAfterSeconds).statement);
      paused = true;
      run.skipped = `FCM: ${result.error}`;
    }
  }
  if (writes.length) await env.DB.batch(writes);
  console.log(JSON.stringify({ message: "support push run", ...run }));
  return run;
}

/**
 * Once a day (the cleanup run): deletes the conversations closed, or with no
 * new message, for more than KEEP_DAYS, with their messages, and clears the
 * address hashes of past days with those days' salts (only today's count
 * needs them).
 */
export async function cleanupSupport(env: Env, now = new Date()): Promise<number> {
  const before = toStoredTime(new Date(now.getTime() - KEEP_DAYS * DAY_MS));
  const today = toStoredTime(now).slice(0, 10);
  const old = "SELECT id FROM support_threads WHERE closed_at < ?1 OR updated_at < ?1";
  const [, threads] = await env.DB.batch([
    env.DB.prepare(`DELETE FROM support_messages WHERE thread_id IN (${old})`).bind(before),
    env.DB.prepare(`DELETE FROM support_threads WHERE id IN (${old})`).bind(before),
    env.DB.prepare("UPDATE support_messages SET ip_day_hash = NULL WHERE ip_day_hash IS NOT NULL AND created_at < ?1").bind(`${today}T00:00:00Z`),
    env.DB.prepare("DELETE FROM support_salts WHERE day < ?1").bind(today),
  ]);
  return threads.meta.changes ?? 0;
}

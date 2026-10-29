// Messages from readers (#220, Yurii 29 Oct; docs/contract.md): a reader
// writes from the app with no login, we reply on the admin page (admin/
// messages.ts), and the reply goes back with a push (./cron.ts). One open
// message at a time: after writing, a reader waits for our reply, or 7 days.
// The phone's id is stored only as its SHA-256, the network address not at all.
import type { Env } from "../env";
import { toStoredTime } from "../fetcher/text";

/** The longest message, from a reader or from us, in characters (Unicode code points). */
export const MAX_TEXT = 2000;
/** A reader waiting for our reply can write again this many days after their latest message. */
export const WAIT_DAYS = 7;
/** At most this many messages a UTC day from one network address. */
export const DAILY_MESSAGES = 5;
export const SUPPORT_LANGS = ["en", "uk", "ru", "es", "de"] as const;
export type SupportLang = (typeof SUPPORT_LANGS)[number];

const DEVICE = /^[A-Za-z0-9_-]{32,128}$/;
const MAX_APP = 32;
const MAX_PUSH_TOKEN = 4096;
const DAY_MS = 86_400_000;

export type ThreadStatus = "waiting" | "answered" | "closed";
export interface Message {
  from: "reader" | "team";
  text: string;
  at: string;
}
/** The conversation as the app gets it. */
export interface Thread {
  status: ThreadStatus;
  messages: Message[];
  canWrite: boolean;
  writeAfter: string | null;
}
/** An answer for the router: its status and JSON body. */
export interface SupportAnswer {
  status: number;
  body: Record<string, unknown>;
}

export async function sha256(text: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  return [...digest].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** A message's text, trimmed, when it is 1 to MAX_TEXT characters; else null. */
export function readText(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const text = value.trim();
  const length = [...text].length;
  return length >= 1 && length <= MAX_TEXT ? text : null;
}

const fail = (status: number, error: string, extra: Record<string, string | null> = {}): SupportAnswer => ({ status, body: { error, ...extra } });

/** A phone's latest conversation with its messages, oldest first (one statement). */
const LATEST = `SELECT t.id, t.status, m.sender, m.text, m.created_at
  FROM support_threads t LEFT JOIN support_messages m ON m.thread_id = t.id
  WHERE t.id = (SELECT id FROM support_threads WHERE device_hash = ?1 ORDER BY created_at DESC, rowid DESC LIMIT 1)
  ORDER BY m.created_at, m.rowid`;

/** The reader's messages today from one address (?1, its hash with the day). */
const SENT_TODAY = "SELECT COUNT(*) AS n FROM support_messages WHERE ip_day_hash = ?1";

/**
 * A new conversation, only while the phone has none that is not closed and
 * the address is under the day's limit, checked in the insert itself so two
 * sends at once cannot both pass. Binds: ?1 id, ?2 device hash, ?3 lang, ?4
 * app, ?5 push token, ?6 now, ?7 address hash, ?8 DAILY_MESSAGES.
 */
const NEW_THREAD = `INSERT INTO support_threads (id, device_hash, status, lang, app, push_token, created_at, updated_at)
  SELECT ?1, ?2, 'waiting', ?3, ?4, ?5, ?6, ?6
  WHERE NOT EXISTS (SELECT 1 FROM support_threads WHERE device_hash = ?2 AND status <> 'closed')
    AND (SELECT COUNT(*) FROM support_messages WHERE ip_day_hash = ?7) < ?8`;

/** The new conversation's first message, when the statement above wrote it. Binds: ?1 id, ?2 thread, ?3 text, ?4 address hash, ?5 now. */
const FIRST_MESSAGE = `INSERT INTO support_messages (id, thread_id, sender, text, ip_day_hash, created_at)
  SELECT ?1, ?2, 'reader', ?3, ?4, ?5 WHERE EXISTS (SELECT 1 FROM support_threads WHERE id = ?2)`;

/**
 * A message in the phone's open conversation, only when the reader may write
 * (the latest message is ours, or theirs is WAIT_DAYS old) and the address is
 * under the limit, in the insert itself. Binds: ?1 id, ?2 thread, ?3 text, ?4
 * address hash, ?5 now, ?6 WAIT_DAYS before now, ?7 DAILY_MESSAGES.
 */
const NEXT_MESSAGE = `INSERT INTO support_messages (id, thread_id, sender, text, ip_day_hash, created_at)
  SELECT ?1, ?2, 'reader', ?3, ?4, ?5
  WHERE EXISTS (SELECT 1 FROM support_threads WHERE id = ?2 AND status <> 'closed')
    AND (COALESCE((SELECT sender FROM support_messages WHERE thread_id = ?2 ORDER BY created_at DESC, rowid DESC LIMIT 1), 'team') = 'team'
         OR COALESCE((SELECT MAX(created_at) FROM support_messages WHERE thread_id = ?2 AND sender = 'reader'), '') <= ?6)
    AND (SELECT COUNT(*) FROM support_messages WHERE ip_day_hash = ?4) < ?7`;

/** The conversation after a message the statement above wrote: waiting for us, with the reader's latest details. */
const CONTINUE_THREAD = `UPDATE support_threads
  SET status = 'waiting', lang = ?2, app = ?3, push_token = COALESCE(?4, push_token), reply_push_pending = 0, updated_at = ?5
  WHERE id = ?1 AND EXISTS (SELECT 1 FROM support_messages WHERE id = ?6)`;

interface Latest {
  id: string;
  status: ThreadStatus;
  messages: Message[];
}

async function latest(env: Env, deviceHash: string): Promise<Latest | null> {
  const { results } = await env.DB.prepare(LATEST)
    .bind(deviceHash)
    .all<{ id: string; status: ThreadStatus; sender: Message["from"] | null; text: string | null; created_at: string | null }>();
  if (!results.length) return null;
  const messages = results.filter((r) => r.sender).map((r) => ({ from: r.sender!, text: r.text ?? "", at: r.created_at ?? "" }));
  return { id: results[0].id, status: results[0].status, messages };
}

/** Whether the reader may write, and into which conversation: a new one, or the open one. */
function verdict(thread: Latest | null, now: Date): { canWrite: boolean; writeAfter: string | null; into: "new" | "open" | null } {
  if (!thread || thread.status === "closed") return { canWrite: true, writeAfter: null, into: "new" };
  const last = thread.messages.at(-1);
  if (!last || last.from === "team") return { canWrite: true, writeAfter: null, into: "open" };
  // The latest message is the reader's: messages are oldest first.
  const after = new Date(Date.parse(last.at) + WAIT_DAYS * DAY_MS);
  if (after <= now) return { canWrite: true, writeAfter: null, into: "open" };
  return { canWrite: false, writeAfter: toStoredTime(after), into: null };
}

function threadJson(thread: Latest | null, now: Date): Thread | null {
  if (!thread) return null;
  const { canWrite, writeAfter } = verdict(thread, now);
  return { status: thread.status, messages: thread.messages, canWrite, writeAfter };
}

/** `GET /v1/support/thread`: the phone's latest conversation, by its id in `X-Support-Device`. */
export async function supportThread(device: string | null, env: Env, now = new Date()): Promise<SupportAnswer> {
  if (!device || !DEVICE.test(device)) return fail(400, "X-Support-Device: 32 to 128 letters, digits, - or _");
  return { status: 200, body: { thread: threadJson(await latest(env, await sha256(device)), now) } };
}

interface Incoming {
  device: string;
  text: string;
  lang: SupportLang;
  app: string;
  push: string | null;
}

function readBody(body: unknown): Incoming | string {
  const b = (body ?? {}) as Record<string, unknown>;
  if (typeof b !== "object" || Array.isArray(b)) return "Expected { device, text, lang, app, push? }";
  if (typeof b.device !== "string" || !DEVICE.test(b.device)) return "device: 32 to 128 letters, digits, - or _";
  const text = readText(b.text);
  if (text === null) return `text: 1 to ${MAX_TEXT} characters`;
  if (!SUPPORT_LANGS.includes(b.lang as SupportLang)) return "lang must be en, uk, ru, es or de";
  if (typeof b.app !== "string" || b.app.length > MAX_APP) return `app: a string of at most ${MAX_APP} characters`;
  if (b.push != null && (typeof b.push !== "string" || b.push.length > MAX_PUSH_TOKEN)) return `push: a string of at most ${MAX_PUSH_TOKEN} characters`;
  return { device: b.device, text, lang: b.lang as SupportLang, app: b.app.trim(), push: (b.push as string | null | undefined) || null };
}

/**
 * `POST /v1/support/messages`: a reader's message. `ip` is CF-Connecting-IP,
 * used only as a hash with the UTC day, to count the day's messages.
 */
export async function postSupportMessage(body: unknown, ip: string | null, env: Env, now = new Date()): Promise<SupportAnswer> {
  const m = readBody(body);
  if (typeof m === "string") return fail(400, m);
  const deviceHash = await sha256(m.device);
  const at = toStoredTime(now);
  const day = at.slice(0, 10);
  const ipHash = await sha256(`${ip ?? "unknown"}|${day}`);
  const weekAgo = toStoredTime(new Date(now.getTime() - WAIT_DAYS * DAY_MS));
  // A second try only when another send changed the conversation between the read and the write.
  for (let attempt = 0; attempt < 2; attempt++) {
    const thread = await latest(env, deviceHash);
    const { writeAfter, into } = verdict(thread, now);
    if (!into) return fail(409, "Waiting for our reply", { writeAfter });
    const sent = (await env.DB.prepare(SENT_TODAY).bind(ipHash).first<number>("n")) ?? 0;
    if (sent >= DAILY_MESSAGES) return fail(429, "Too many messages today", { resetsAt: toStoredTime(new Date(Date.parse(`${day}T00:00:00Z`) + DAY_MS)) });
    const messageId = crypto.randomUUID();
    const threadId = into === "new" ? crypto.randomUUID() : thread!.id;
    const [written] = await env.DB.batch(
      into === "new"
        ? [
            env.DB.prepare(NEW_THREAD).bind(threadId, deviceHash, m.lang, m.app, m.push, at, ipHash, DAILY_MESSAGES),
            env.DB.prepare(FIRST_MESSAGE).bind(messageId, threadId, m.text, ipHash, at),
          ]
        : [
            env.DB.prepare(NEXT_MESSAGE).bind(messageId, threadId, m.text, ipHash, at, weekAgo, DAILY_MESSAGES),
            env.DB.prepare(CONTINUE_THREAD).bind(threadId, m.lang, m.app, m.push, at, messageId),
          ],
    );
    if (written.meta.changes) return { status: 200, body: { thread: threadJson(await latest(env, deviceHash), now) } };
  }
  return fail(503, "Busy, try again");
}
